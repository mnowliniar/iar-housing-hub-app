//
//  HubCache.swift
//  ReportsApp
//
//  Most of what the app shows changes once a week: the dashboard numbers,
//  the insights, the reports, the blogs. Every reply the app gets is kept
//  on disk, and a screen shows what it has at once. Then one small request
//  to /app/fresh/ says whether that family of data has moved since, and
//  only then does the app fetch again.
//

import Foundation
import CryptoKit

/// Which stamp on /app/fresh/ governs a cached reply.
enum CacheFamily: String {
    case data       // chart builds: dashboard tiles, reports, insights
    case blogs      // published posts
    case catalog    // the lists of reports, vizzes, places
    case member     // this member's own things: always re-checked
}

/// The stamps the Hub published last, fetched at most every few minutes.
actor Freshness {
    static let shared = Freshness()

    private var stamps: [String: String]?
    private var fetchedAt: Date?
    private var inflight: Task<[String: String]?, Never>?
    private let maxAge: TimeInterval = 5 * 60

    /// nil when the Hub can't be reached; callers then trust what they have.
    func current() async -> [String: String]? {
        if let stamps, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge {
            return stamps
        }
        if let inflight { return await inflight.value }
        let task = Task<[String: String]?, Never> {
            guard let url = URL(string: "https://\(AppIdentity.hubHost)/app/fresh/") else { return nil }
            var request = URLRequest.app(url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let reply = try? await URLSession.shared.data(for: request),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any] else { return nil }
            var out: [String: String] = [:]
            for (key, value) in json {
                if let text = value as? String { out[key] = text }
            }
            return out
        }
        inflight = task
        let result = await task.value
        inflight = nil
        if let result {
            stamps = result
            fetchedAt = Date()
        }
        return result
    }

    /// Coming back to the app: ask again next time.
    func invalidate() {
        fetchedAt = nil
    }
}

/// One cached reply.
private struct CacheEntry: Codable {
    let family: String
    let stamp: String
    let savedAt: Date
    let body: Data
}

enum HubCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("hub-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let memory = NSCache<NSString, NSData>()
    /// Without a stamp to compare, a reply this old is fetched again.
    private static let fallbackMaxAge: TimeInterval = 6 * 60 * 60

    // MARK: Reading

    /// The reply for `url`: what's on disk when the family hasn't moved,
    /// otherwise the network's (kept for next time). Falls back to the
    /// cached copy when the network fails, so a dead spot shows last week.
    static func data(_ url: URL, family: CacheFamily) async -> Data? {
        let cached = load(url)
        let stamps = await Freshness.shared.current()
        if let cached, !needsRefresh(cached, family: family, stamps: stamps) {
            return cached.body
        }
        if let fresh = await download(url, family: family, stamps: stamps) {
            return fresh
        }
        return cached?.body
    }

    /// Decodes `data(_:family:)`.
    static func value<T: Decodable>(_ url: URL, family: CacheFamily, as type: T.Type) async -> T? {
        guard let bytes = await data(url, family: family) else { return nil }
        return try? JSONDecoder().decode(T.self, from: bytes)
    }

    /// Show-then-check: yields the decoded cached reply at once when there
    /// is one, then the network's when the family moved (or nothing was
    /// cached). Finishes after at most two values.
    static func stream<T>(_ url: URL, family: CacheFamily,
                          decode: @escaping (Data) throws -> T) -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task {
                let cached = load(url)
                if let cached, let value = try? decode(cached.body) {
                    continuation.yield(value)
                }
                let stamps = await Freshness.shared.current()
                if Task.isCancelled { continuation.finish(); return }
                let stale = cached.map { needsRefresh($0, family: family, stamps: stamps) } ?? true
                if stale, let fresh = await download(url, family: family, stamps: stamps),
                   !Task.isCancelled, let value = try? decode(fresh) {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func stream<T: Decodable>(_ url: URL, family: CacheFamily, as type: T.Type) -> AsyncStream<T> {
        stream(url, family: family) { try JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: Housekeeping

    /// Everything, on sign-out: the member family is theirs.
    static func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Drops replies nothing has asked for in two weeks. Run off the main thread.
    static func prune(olderThan days: Int = 14) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: Plumbing

    private static func needsRefresh(_ entry: CacheEntry, family: CacheFamily, stamps: [String: String]?) -> Bool {
        if family == .member { return true }
        if let stamp = stamps?[family.rawValue] {
            return stamp != entry.stamp || stamp.isEmpty
        }
        return Date().timeIntervalSince(entry.savedAt) > fallbackMaxAge
    }

    private static func download(_ url: URL, family: CacheFamily, stamps: [String: String]?) async -> Data? {
        var request = URLRequest.app(url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let reply = try? await URLSession.shared.data(for: request),
              let http = reply.1 as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        store(reply.0, for: url, family: family, stamp: stamps?[family.rawValue] ?? "")
        return reply.0
    }

    private static func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("plist")
    }

    private static func load(_ url: URL) -> CacheEntry? {
        let file = fileURL(for: url)
        let key = file.lastPathComponent as NSString
        let raw: Data
        if let hit = memory.object(forKey: key) {
            raw = hit as Data
        } else if let disk = try? Data(contentsOf: file) {
            raw = disk
            memory.setObject(disk as NSData, forKey: key)
        } else {
            return nil
        }
        guard let entry = try? PropertyListDecoder().decode(CacheEntry.self, from: raw) else { return nil }
        // Touch it so pruning keeps what is still read.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return entry
    }

    private static func store(_ data: Data, for url: URL, family: CacheFamily, stamp: String) {
        let entry = CacheEntry(family: family.rawValue, stamp: stamp, savedAt: Date(), body: data)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let raw = try? encoder.encode(entry) else { return }
        let file = fileURL(for: url)
        memory.setObject(raw as NSData, forKey: file.lastPathComponent as NSString)
        try? raw.write(to: file, options: .atomic)
    }
}
