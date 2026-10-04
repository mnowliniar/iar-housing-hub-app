//
//  MarketPackModel.swift
//  ReportsApp
//
//  State for the native Market Pack screen: which market is up, this
//  month's assets for it (rendering the ones that don't exist yet), the
//  reel's progress, and the member's setup.
//

import SwiftUI
import UIKit

/// One thing to swipe through: the Story card, a square, or the reel.
struct PackAsset: Identifiable, Equatable {
    enum Kind: Equatable {
        case story
        case square(index: Int, vizID: Int)
        case reel
    }

    let id: String
    let kind: Kind
    var key: String
    var url: URL?
    var ready: Bool
    var failed = false
    var title: String
    var caption: String?
    var statLine: String?

    var isReel: Bool { kind == .reel }
    var aspect: CGFloat {
        if case .square = kind { return 1 }
        return 9.0 / 16.0
    }
    var eyebrow: String {
        switch kind {
        case .story: return "Story · 1080 × 1920"
        case .square: return "Square · 1080 × 1080"
        case .reel: return "Reel · 30 seconds"
        }
    }
    /// The filename the share sheet and Files see.
    var filename: String {
        let slug = title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        switch kind {
        case .story: return "story-1080x1920.png"
        case .square: return "\(slug.isEmpty ? "card" : slug)-1080x1080.png"
        case .reel: return "reel-1080x1920.mp4"
        }
    }
}

enum ReelState: Equatable {
    case idle                 // can be made on demand
    case emailOnly            // this deployment renders reels for the email only
    case queued
    case rendering
    case ready(URL)
    case failed(String)

    var inProgress: Bool { self == .queued || self == .rendering }
}

/// Hands render slots to two workers, story first.
private actor SlotQueue {
    private var slots: [String]
    init(_ slots: [String]) { self.slots = slots }
    func next() -> String? { slots.isEmpty ? nil : slots.removeFirst() }
}

struct PackShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
    let fileURL: URL?

    func cleanup() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

@MainActor
final class MarketPackModel: ObservableObject {
    @Published var setup: PackSetup?
    @Published var currentGeoID: Int?
    @Published var issue: PackIssue?
    @Published var assets: [PackAsset] = []
    @Published var reel: ReelState = .idle
    @Published var loadingSetup = true
    @Published var loadingIssue = false
    @Published var error: SparkLibraryService.ServiceError?
    @Published var busyAssetID: String?     // an asset being fetched for the share sheet
    @Published var exporting = false
    @Published var shareItem: PackShareItem? {
        didSet { oldValue?.cleanup() }   // the previous temp file, once the sheet is gone
    }
    @Published var notice: String?

    /// The market to show when the member's pack has none yet.
    var fallbackGeoID: Int = 18

    private var renderTask: Task<Void, Never>?
    private var reelTask: Task<Void, Never>?
    private var viewedGeoIDs = Set<Int>()

    var markets: [PackMarket] { setup?.markets ?? [] }
    var maxMarkets: Int { setup?.maxMarkets ?? 5 }
    var canAddMarket: Bool { markets.count < maxMarkets }
    var hasOwnMarkets: Bool { !markets.isEmpty }

    /// The label for the market on screen, from the setup or the issue.
    var currentLabel: String {
        if let m = markets.first(where: { $0.geoID == currentGeoID }) { return m.geoLabel }
        return issue?.geoLabel ?? "Your market"
    }

    // MARK: Loading

    func load() async {
        loadingSetup = true
        error = nil
        do {
            let fetched = try await MarketPackService.setup()
            setup = fetched
            loadingSetup = false
            let geoID = fetched.markets.first?.geoID ?? fallbackGeoID
            await select(geoID)
        } catch {
            loadingSetup = false
            self.error = (error as? SparkLibraryService.ServiceError) ?? .init(message: error.localizedDescription)
        }
    }

    func select(_ geoID: Int) async {
        guard geoID != currentGeoID || issue == nil else { return }
        renderTask?.cancel()
        reelTask?.cancel()
        currentGeoID = geoID
        issue = nil
        assets = []
        reel = .idle
        await loadIssue()
    }

    /// Same market, fresh look at what exists (after the setup changes).
    func reload() async {
        renderTask?.cancel()
        reelTask?.cancel()
        issue = nil
        assets = []
        reel = .idle
        await loadIssue()
    }

    private func loadIssue() async {
        guard let geoID = currentGeoID else { return }
        loadingIssue = true
        error = nil
        defer { loadingIssue = false }
        do {
            let data = try await MarketPackService.data(geoID: geoID)
            guard currentGeoID == geoID else { return }
            issue = data.issue
            assets = Self.assets(from: data)
            if !viewedGeoIDs.contains(geoID) {
                viewedGeoIDs.insert(geoID)
                EventTracker.fire(.viewMarketPack, metadata: [
                    "geoid": String(geoID),
                    "geo_label": data.issue.geoLabel ?? "",
                ])
            }
            setReelState(from: data.video)
            startRendering(data.pending ?? [], geoID: geoID)
            if case .idle = reel { checkReelAlreadyRunning(geoID: geoID) }
        } catch {
            guard currentGeoID == geoID else { return }
            self.error = (error as? SparkLibraryService.ServiceError) ?? .init(message: error.localizedDescription)
        }
    }

    private static func assets(from data: PackData) -> [PackAsset] {
        let issue = data.issue
        let pending = Set(data.pending ?? [])
        var out: [PackAsset] = []
        let leadNouns = (issue.images?.squares ?? []).compactMap { sq -> String? in
            guard let viz = sq.vizID else { return nil }
            return issue.stat(forViz: viz)?.title
        }
        if let story = issue.images?.story {
            out.append(PackAsset(
                id: "story", kind: .story, key: story.key, url: URL(string: story.url),
                ready: !pending.contains("story"), title: "Story",
                caption: nil,
                statLine: leadNouns.isEmpty ? nil : leadNouns.joined(separator: " · ")))
        }
        for (i, sq) in (issue.images?.squares ?? []).enumerated() {
            let viz = sq.vizID ?? 0
            let stat = issue.stat(forViz: viz)
            var line: String?
            if let value = stat?.displayValue, !value.isEmpty {
                line = [value, stat?.valueLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            }
            out.append(PackAsset(
                id: String(i), kind: .square(index: i, vizID: viz), key: sq.key, url: URL(string: sq.url),
                ready: !pending.contains(String(i)), title: stat?.title ?? "Card \(i + 1)",
                caption: issue.caption(forViz: viz), statLine: line))
        }
        out.append(PackAsset(
            id: "reel", kind: .reel, key: data.video?.key ?? "",
            url: data.video?.url.flatMap(URL.init(string:)), ready: data.video?.ready ?? false,
            title: "Reel", caption: nil, statLine: nil))
        return out
    }

    // MARK: Rendering the missing cards

    private func startRendering(_ pending: [String], geoID: Int) {
        guard !pending.isEmpty else { return }
        let queue = SlotQueue(pending)
        renderTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<2 {
                    group.addTask {
                        while !Task.isCancelled, let slot = await queue.next() {
                            await self?.render(slot: slot, geoID: geoID)
                        }
                    }
                }
            }
        }
    }

    private func render(slot: String, geoID: Int) async {
        do {
            let image = try await MarketPackService.render(geoID: geoID, slot: slot)
            guard currentGeoID == geoID, let i = assets.firstIndex(where: { $0.id == slot }) else { return }
            // A fresh query string: the URL may have been a 404 a moment ago.
            let stamp = Int(Date().timeIntervalSince1970)
            assets[i].key = image.key
            assets[i].url = URL(string: image.url + "?r=\(stamp)")
            assets[i].ready = true
        } catch {
            guard currentGeoID == geoID, let i = assets.firstIndex(where: { $0.id == slot }) else { return }
            assets[i].failed = true
        }
    }

    func retryRender(_ asset: PackAsset) {
        guard let geoID = currentGeoID, let i = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[i].failed = false
        Task { await render(slot: asset.id, geoID: geoID) }
    }

    // MARK: Reel

    private func setReelState(from video: PackVideo?) {
        if video?.ready == true, let raw = video?.url, let url = URL(string: raw) {
            reel = .ready(url)
            markReelReady(url)
        } else if video?.ondemand == false {
            reel = .emailOnly
        } else {
            reel = .idle
        }
    }

    private func markReelReady(_ url: URL) {
        if let i = assets.firstIndex(where: { $0.isReel }) {
            assets[i].url = url
            assets[i].ready = true
        }
    }

    /// A reel started on the web, or on an earlier visit, keeps going.
    private func checkReelAlreadyRunning(geoID: Int) {
        reelTask = Task { [weak self] in
            guard let status = try? await MarketPackService.reelStatus(geoID: geoID) else { return }
            await self?.apply(status, geoID: geoID, thenPoll: true)
        }
    }

    func createReel() {
        guard let geoID = currentGeoID else { return }
        reel = .queued
        reelTask?.cancel()
        reelTask = Task { [weak self] in
            do {
                let status = try await MarketPackService.startReel(geoID: geoID)
                await self?.apply(status, geoID: geoID, thenPoll: true)
            } catch {
                await self?.reelFailed(error, geoID: geoID)
            }
        }
    }

    private func reelFailed(_ error: Error, geoID: Int) {
        guard currentGeoID == geoID else { return }
        let text = (error as? SparkLibraryService.ServiceError)?.message ?? error.localizedDescription
        reel = .failed(text)
    }

    private func apply(_ status: PackReelStatus, geoID: Int, thenPoll: Bool) async {
        guard currentGeoID == geoID else { return }
        if status.ready == true, let raw = status.video?.url, let url = URL(string: raw) {
            let stamp = Int(Date().timeIntervalSince1970)
            let fresh = URL(string: raw + "?r=\(stamp)") ?? url
            reel = .ready(fresh)
            if let key = status.video?.key, let i = assets.firstIndex(where: { $0.isReel }) {
                assets[i].key = key
            }
            markReelReady(fresh)
            return
        }
        if status.failed == true {
            reel = .failed(status.error ?? "Reel rendering hit a snag. Try again.")
            return
        }
        let running = status.started == true || status.running == true
        guard running else {
            if case .idle = reel { return }
            if reel.inProgress { reel = .idle }
            return
        }
        reel = status.phase == "queued" ? .queued : .rendering
        guard thenPoll else { return }
        // Up to five minutes, every five seconds, like the web page.
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled || currentGeoID != geoID { return }
            guard let next = try? await MarketPackService.reelStatus(geoID: geoID) else { continue }
            if next.ready == true || next.failed == true {
                await apply(next, geoID: geoID, thenPoll: false)
                return
            }
            if next.phase == "rendering" { reel = .rendering }
        }
        reel = .failed("Still rendering. Check back in a few minutes.")
    }

    // MARK: Sharing

    /// Fetches the asset and opens the share sheet: images as images (so
    /// Save Image and Instagram are there), the reel as a file.
    func shareAsset(_ asset: PackAsset) async {
        guard asset.ready, !asset.key.isEmpty else { return }
        busyAssetID = asset.id
        defer { busyAssetID = nil }
        do {
            let data = try await MarketPackService.download(key: asset.key)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(asset.filename)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            if asset.isReel {
                shareItem = PackShareItem(items: [url], fileURL: url)
            } else if let image = UIImage(data: data) {
                let title = "\(currentLabel) · \(asset.title)"
                shareItem = PackShareItem(items: [ShareImageItemSource(fileURL: url, image: image, title: title)], fileURL: url)
            } else {
                shareItem = PackShareItem(items: [url], fileURL: url)
            }
        } catch {
            notice = (error as? SparkLibraryService.ServiceError)?.message ?? "Couldn't fetch that right now."
        }
    }

    func exportAll() async {
        guard let geoID = currentGeoID else { return }
        exporting = true
        defer { exporting = false }
        do {
            let (data, name) = try await MarketPackService.exportZip(geoID: geoID)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            shareItem = PackShareItem(items: [url], fileURL: url)
        } catch {
            notice = (error as? SparkLibraryService.ServiceError)?.message ?? "Couldn't build the download."
        }
    }

    // MARK: Setup

    func addMarket(_ geo: Geo) async {
        guard canAddMarket, !markets.contains(where: { $0.geoID == geo.geoid }) else { return }
        let next = markets + [PackMarket(geoID: geo.geoid, geoLabel: geo.displayName)]
        await saveMarkets(next, thenSelect: geo.geoid)
    }

    func removeMarket(_ market: PackMarket) async {
        let next = markets.filter { $0.geoID != market.geoID }
        let selectNext = market.geoID == currentGeoID ? (next.first?.geoID ?? fallbackGeoID) : nil
        await saveMarkets(next, thenSelect: selectNext)
    }

    private func saveMarkets(_ next: [PackMarket], thenSelect geoID: Int?) async {
        do {
            setup = try await MarketPackService.saveOptions(markets: next)
            if let geoID { await select(geoID) }
        } catch {
            notice = (error as? SparkLibraryService.ServiceError)?.message ?? "Couldn't save your markets."
        }
    }

    /// The Options sheet's result. Cards depend on the indicator set and the
    /// look, so those two reload the market; the voice changes the script.
    func save(combo: String, preset: String, template: String, markets: [PackMarket], active: Bool) async {
        let before = setup
        do {
            let saved = try await MarketPackService.saveOptions(combo: combo, preset: preset, template: template, markets: markets)
            setup = saved
            if active != (before?.active ?? false) {
                try await MarketPackService.setActive(active)
                setup?.active = active
            }
            let marketsChanged = before.map { $0.markets.map(\.geoID) } != markets.map(\.geoID)
            if let current = currentGeoID, marketsChanged, !markets.contains(where: { $0.geoID == current }) {
                await select(markets.first?.geoID ?? fallbackGeoID)
            } else if before?.combo != saved.combo || before?.template != saved.template || before?.preset != saved.preset {
                await reload()
            }
        } catch {
            notice = (error as? SparkLibraryService.ServiceError)?.message ?? "Couldn't save your options."
        }
    }

    func setActive(_ active: Bool) async {
        let previous = setup?.active ?? false
        setup?.active = active
        do {
            try await MarketPackService.setActive(active)
        } catch {
            setup?.active = previous
            notice = (error as? SparkLibraryService.ServiceError)?.message ?? "Couldn't change the monthly email."
        }
    }

    func stop() {
        renderTask?.cancel()
        reelTask?.cancel()
    }
}
