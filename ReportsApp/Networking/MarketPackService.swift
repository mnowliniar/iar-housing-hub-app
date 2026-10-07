//
//  MarketPackService.swift
//  ReportsApp
//
//  The Market Pack is a month's social assets for a market: a Story card,
//  three square cards, a 30-second reel, and the words to post with them.
//  The Hub builds them; this is the app's line to those endpoints.
//

import Foundation

// MARK: - Shapes

struct PackMarket: Codable, Identifiable, Hashable {
    let geoID: Int
    let geoLabel: String

    var id: Int { geoID }

    enum CodingKeys: String, CodingKey {
        case geoID = "geo_id"
        case geoLabel = "geo_label"
    }
}

struct PackChoice: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let nouns: [String]?

    /// "Median Sale Price · Closed Sales · Homes for Sale"
    var detail: String? {
        guard let nouns, !nouns.isEmpty else { return nil }
        return nouns.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The member's setup plus everything they can choose from.
struct PackSetup: Decodable {
    var markets: [PackMarket]
    var active: Bool
    var combo: String
    var template: String
    var preset: String
    var maxMarkets: Int
    var combos: [PackChoice]
    var templates: [PackChoice]
    var presets: [PackChoice]

    enum CodingKeys: String, CodingKey {
        case markets, active, combo, template, preset, combos, templates, presets
        case maxMarkets = "max_markets"
    }

    func label(for id: String, in choices: [PackChoice]) -> String {
        choices.first(where: { $0.id == id })?.label ?? id
    }

    /// One line for the subscription card: "The classics · Hub teal · Balanced".
    var summary: String {
        [label(for: combo, in: combos), label(for: template, in: templates), label(for: preset, in: presets)]
            .joined(separator: " · ")
    }
}

struct PackImage: Decodable {
    let key: String
    let url: String
    let w: Int?
    let h: Int?
    let vizID: Int?

    enum CodingKeys: String, CodingKey {
        case key, url, w, h
        case vizID = "viz_id"
    }
}

struct PackImages: Decodable {
    let story: PackImage?
    let squares: [PackImage]?
}

struct PackStat: Decodable {
    let vizID: Int?
    let title: String?
    let displayValue: String?
    let valueLabel: String?
    let window: String?

    enum CodingKeys: String, CodingKey {
        case title, window
        case vizID = "viz_id"
        case displayValue = "display_value"
        case valueLabel = "value_label"
    }
}

struct PackIssue: Decodable {
    let geoID: Int
    let geoLabel: String?
    let month: String?
    let monthLabel: String?
    let stats: [PackStat]?
    let script: String?
    let captions: [String: String?]?
    /// One spoken sentence per indicator, for the presentation slides.
    let talkingPoints: [String: String?]?
    let images: PackImages?

    enum CodingKeys: String, CodingKey {
        case month, stats, script, captions, images
        case geoID = "geo_id"
        case geoLabel = "geo_label"
        case monthLabel = "month_label"
        case talkingPoints = "talking_points"
    }

    func caption(forViz vizID: Int) -> String? {
        guard let text = captions?[String(vizID)] ?? nil, !text.isEmpty else { return nil }
        return text
    }

    func talkingPoint(forViz vizID: Int) -> String? {
        guard let text = talkingPoints?[String(vizID)] ?? nil, !text.isEmpty else { return nil }
        return text
    }

    func stat(forViz vizID: Int) -> PackStat? {
        stats?.first(where: { $0.vizID == vizID })
    }
}

struct PackVideo: Decodable {
    let key: String?
    let url: String?
    let ready: Bool?
    let ondemand: Bool?
}

struct PackData: Decodable {
    let issue: PackIssue
    let pending: [String]?
    let video: PackVideo?
    let picks: [Int]?
}

/// What the reel endpoint says, on POST and on each poll.
struct PackReelStatus: Decodable {
    let ready: Bool?
    let started: Bool?
    let running: Bool?
    let failed: Bool?
    let phase: String?
    let error: String?
    let video: PackVideo?
}

// MARK: - Service

enum MarketPackService {
    typealias ServiceError = SparkLibraryService.ServiceError

    private static let base = ChatManager.serverBaseURL
    private static let decoder = JSONDecoder()

    /// The member's setup and the catalog of choices.
    static func setup() async throws -> PackSetup {
        try await get("/market-pack/options/", as: PackSetup.self)
    }

    /// Saves any of the four settings; nil leaves one alone. Returns the
    /// setup as the server now holds it.
    static func saveOptions(combo: String? = nil, preset: String? = nil, template: String? = nil,
                            markets: [PackMarket]? = nil) async throws -> PackSetup {
        var body: [String: Any] = [:]
        if let combo { body["combo"] = combo }
        if let preset { body["preset"] = preset }
        if let template { body["template"] = template }
        if let markets {
            body["markets"] = markets.map { ["geo_id": $0.geoID, "geo_label": $0.geoLabel] }
        }
        return try await post("/market-pack/options/", body, as: PackSetup.self)
    }

    /// The monthly email, on or off.
    static func setActive(_ active: Bool) async throws {
        struct Reply: Decodable { let sub: Sub?; struct Sub: Decodable { let active: Bool? } }
        _ = try await post("/market-pack/subscribe/", ["active": active], as: Reply.self)
    }

    /// This month's pack for a market, with the list of cards still to render.
    static func data(geoID: Int) async throws -> PackData {
        try await post("/market-pack/data/", ["geo_id": geoID], as: PackData.self, timeout: 120)
    }

    /// Renders one card ("story" or a square's index) for the member's setup.
    static func render(geoID: Int, slot: String) async throws -> PackImage {
        struct Reply: Decodable { let image: PackImage }
        return try await post("/market-pack/render/", ["geo_id": geoID, "slot": slot], as: Reply.self, timeout: 120).image
    }

    static func startReel(geoID: Int) async throws -> PackReelStatus {
        try await post("/market-pack/video/", ["geo_id": geoID], as: PackReelStatus.self)
    }

    static func reelStatus(geoID: Int) async throws -> PackReelStatus {
        try await get("/market-pack/video/?geo_id=\(geoID)", as: PackReelStatus.self)
    }

    /// One asset's bytes, through the Hub so the download is counted.
    static func download(key: String) async throws -> Data {
        var parts = URLComponents(string: base + "/market-pack/download/")
        parts?.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = parts?.url else { throw ServiceError(message: "Bad address") }
        var request = URLRequest.app(url)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return data
    }

    /// Everything for one market as a zip: the cards, the reel when it
    /// exists, the script and the captions. Returns the bytes and a filename.
    static func exportZip(geoID: Int) async throws -> (Data, String) {
        guard let url = URL(string: base + "/market-pack/export/?geo_id=\(geoID)") else {
            throw ServiceError(message: "Bad address")
        }
        var request = URLRequest.app(url)
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        var name = "market-pack.zip"
        if let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=\"") {
            let rest = disposition[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") { name = String(rest[..<end]) }
        }
        return (data, name)
    }

    // MARK: Plumbing

    private static func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: base + path) else { throw ServiceError(message: "Bad address") }
        let (data, response) = try await URLSession.shared.data(for: .app(url))
        try check(response, data)
        return try decoder.decode(T.self, from: data)
    }

    private static func post<T: Decodable>(_ path: String, _ body: [String: Any], as type: T.Type,
                                           timeout: TimeInterval = 60) async throws -> T {
        guard let url = URL(string: base + path) else { throw ServiceError(message: "Bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())
        try check(response, data)
        return try decoder.decode(T.self, from: data)
    }

    /// Non-2xx replies carry `{"error": "..."}`; a 403 means the token is
    /// no longer good, which the screen turns into a sign-in button.
    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let text = json?["error"] as? String
        if http.statusCode == 403 || http.statusCode == 401 {
            throw ServiceError(message: "Sign in again to open your Market Pack.", needsSignIn: true)
        }
        if let text, !text.isEmpty, text != "not_logged_in" {
            throw ServiceError(message: text)
        }
        throw ServiceError(message: "The Hub answered \(http.statusCode). Try again in a minute.")
    }
}
