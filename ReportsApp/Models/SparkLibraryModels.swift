//
//  SparkLibraryModels.swift
//  ReportsApp
//
//  Recipes, schedules and runs as the Hub's /recipes/, /schedules/ and
//  /runs/ endpoints return them. Every field but the id is optional or has a
//  default: starters and member recipes carry different keys, and a new
//  server field must never stop the list from loading.
//

import Foundation

/// A saved answer shape a member runs for any place. Starters (id
/// "starter_…") are the Hub's own templates.
struct SparkRecipe: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let uses: Int
    let lastUsed: String?
    let formats: [String]
    let blurb: String?
    let hasGeoSlot: Bool
    let exampleGeo: String?
    /// "ask" prompts for the area each run; "fixed" always uses geoLabel.
    let geoMode: String?
    let geoLabel: String?
    let segment: SparkRecipeSegment?
    /// "starter" or "user".
    let scope: String

    var isStarter: Bool { scope == "starter" || id.hasPrefix("starter_") }

    /// The area has to be typed in before a run.
    var needsArea: Bool { hasGeoSlot && geoMode != "fixed" }

    /// "Email · 3 runs", like the web's recipe cards.
    var subtitle: String {
        let format = formats.first.map { $0.capitalized } ?? "Answer"
        if isStarter { return blurb ?? format }
        return "\(format) · " + (uses == 0 ? "not run yet" : uses == 1 ? "1 run" : "\(uses) runs")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, uses, formats, format, blurb, segment, scope
        case lastUsed = "last_used"
        case hasGeoSlot = "has_geo_slot"
        case exampleGeo = "example_geo"
        case geoMode = "geo_mode"
        case geoLabel = "geo_label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Recipe"
        uses = (try? c.decode(Int.self, forKey: .uses)) ?? 0
        lastUsed = try? c.decode(String.self, forKey: .lastUsed)
        if let list = try? c.decode([String].self, forKey: .formats), !list.isEmpty {
            formats = list
        } else if let one = try? c.decode(String.self, forKey: .format) {
            formats = [one]
        } else {
            formats = []
        }
        blurb = try? c.decode(String.self, forKey: .blurb)
        hasGeoSlot = (try? c.decode(Bool.self, forKey: .hasGeoSlot)) ?? false
        exampleGeo = try? c.decode(String.self, forKey: .exampleGeo)
        geoMode = try? c.decode(String.self, forKey: .geoMode)
        geoLabel = try? c.decode(String.self, forKey: .geoLabel)
        segment = try? c.decode(SparkRecipeSegment.self, forKey: .segment)
        scope = (try? c.decode(String.self, forKey: .scope)) ?? "user"
    }
}

/// A recipe's market focus: property type, price band or construction.
struct SparkRecipeSegment: Decodable, Equatable, Hashable {
    let concept: String
    /// "ask" prompts for values each run; "fixed" uses `values`.
    let mode: String
    let values: [String]

    var asks: Bool { mode == "ask" }

    enum CodingKeys: String, CodingKey { case concept, mode, values }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        concept = try c.decode(String.self, forKey: .concept)
        mode = (try? c.decode(String.self, forKey: .mode)) ?? "fixed"
        values = (try? c.decode([String].self, forKey: .values)) ?? []
    }
}

/// /recipes/segments/: concept -> label and value labels.
struct SparkSegmentCatalog: Decodable {
    struct Concept: Decodable {
        let label: String
        let values: [String: String]
    }
    let segments: [String: Concept]

    /// Values in a stable order, labeled.
    func options(for concept: String) -> [SparkSegmentOption] {
        guard let entry = segments[concept] else { return [] }
        return entry.values
            .map { SparkSegmentOption(value: $0.key, label: $0.value) }
            .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }
}

struct SparkSegmentOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

/// A recipe plus a place and a cadence. Runs when that cadence's data lands.
struct SparkSchedule: Decodable, Identifiable, Equatable {
    let id: String
    let recipeID: String
    let recipeName: String
    let cadence: String
    let geoLabel: String
    let active: Bool
    let lastRun: String?
    let lastStatus: String?
    let lastThreadID: String?

    var cadenceLabel: String { cadence == "weekly" ? "Weekly" : "Monthly" }

    enum CodingKeys: String, CodingKey {
        case id, cadence, active
        case recipeID = "recipe_id"
        case recipeName = "recipe_name"
        case geoLabel = "geo_label"
        case lastRun = "last_run"
        case lastStatus = "last_status"
        case lastThreadID = "last_thread_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        recipeID = (try? c.decode(String.self, forKey: .recipeID)) ?? ""
        recipeName = (try? c.decode(String.self, forKey: .recipeName)) ?? "Recipe"
        cadence = (try? c.decode(String.self, forKey: .cadence)) ?? "monthly"
        geoLabel = (try? c.decode(String.self, forKey: .geoLabel)) ?? ""
        active = (try? c.decode(Bool.self, forKey: .active)) ?? true
        lastRun = try? c.decode(String.self, forKey: .lastRun)
        lastStatus = try? c.decode(String.self, forKey: .lastStatus)
        lastThreadID = try? c.decode(String.self, forKey: .lastThreadID)
    }
}

/// One run of a recipe, by hand or by a schedule. `threadID` is the chat it
/// produced.
struct SparkRun: Decodable, Identifiable, Equatable {
    let id: Int
    let recipeName: String
    let scheduleID: String?
    /// manual | schedule | run_now
    let trigger: String
    let geoLabel: String
    let threadID: String?
    /// running | ok | failed
    let status: String
    let message: String?
    let started: String?
    let cadence: String?

    /// A failed run or one without a chat can't be opened.
    var canOpen: Bool { !(threadID ?? "").isEmpty && status != "failed" }

    /// "Run by hand · Carmel · 3h ago", the web's run subtitle.
    var subtitle: String {
        let cadenceWord = cadence == "weekly" ? "Weekly" : "Monthly"
        let how: String
        switch trigger {
        case "manual": how = "Run by hand"
        case "run_now": how = "\(cadenceWord), run now"
        default: how = cadenceWord
        }
        let ago = SparkDates.ago(started)
        let when: String
        switch status {
        case "failed": when = ago.isEmpty ? "failed" : "failed \(ago)"
        case "running": when = ago.isEmpty ? "running" : "running \(ago)"
        default: when = ago
        }
        var parts = [how]
        if !geoLabel.isEmpty { parts.append(geoLabel) }
        if !when.isEmpty { parts.append(when) }
        if status == "failed", let message, !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case id, trigger, status, message, started, cadence
        case recipeName = "recipe_name"
        case scheduleID = "schedule_id"
        case geoLabel = "geo_label"
        case threadID = "thread_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        recipeName = (try? c.decode(String.self, forKey: .recipeName)) ?? "Recipe"
        scheduleID = try? c.decode(String.self, forKey: .scheduleID)
        trigger = (try? c.decode(String.self, forKey: .trigger)) ?? "manual"
        geoLabel = (try? c.decode(String.self, forKey: .geoLabel)) ?? ""
        threadID = try? c.decode(String.self, forKey: .threadID)
        status = (try? c.decode(String.self, forKey: .status)) ?? "ok"
        message = try? c.decode(String.self, forKey: .message)
        started = try? c.decode(String.self, forKey: .started)
        cadence = try? c.decode(String.self, forKey: .cadence)
    }
}

enum SparkDates {
    /// Reads the Hub's timestamps: ISO 8601 with or without fractional
    /// seconds or an offset. Times without an offset are UTC.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: value) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: value) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        // Python's isoformat(): microseconds, with or without "+00:00".
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxxxx", "yyyy-MM-dd'T'HH:mm:ssxxxxx",
                       "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = format
            if let d = f.date(from: value) { return d }
        }
        return nil
    }

    /// "just now", "12m ago", "3h ago", "yesterday", "Sep 3". Matches the web.
    static func ago(_ value: String?) -> String {
        guard let date = parse(value) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }
}
