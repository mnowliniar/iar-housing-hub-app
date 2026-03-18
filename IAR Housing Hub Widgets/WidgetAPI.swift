//
//  WidgetAPI.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import Foundation

enum WidgetAPI {
    // Change these defaults as needed
    static let geoID = "18097"   // Marion County
    static let vizID = "25"      // Example: Inventory
    static let proptype = "all"

    static func fetchTile() async -> WidgetTile? {
        guard let url = makeURL() else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(DashboardResponse.self, from: data)
            return decoded.results.first.flatMap(mapGeo)
        } catch {
            print("Widget fetch error:", error)
            return nil
        }
    }

    private static func makeURL() -> URL? {
        var comps = URLComponents(string: "https://data.indianarealtors.com/api/viz_set/\(proptype)/")
        comps?.queryItems = [
            URLQueryItem(name: "geo_ids", value: geoID),
            URLQueryItem(name: "viz_ids", value: vizID),
            URLQueryItem(name: "facts", value: "fact1,fact2,fact3"),
            URLQueryItem(name: "window", value: "12"),
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "fmt", value: "nested"),
            URLQueryItem(name: "compose", value: "0")
        ]
        return comps?.url
    }

    private static func mapGeo(_ geo: DashboardResponse.Geo) -> WidgetTile? {
        guard let viz = geo.viz.first else { return nil }

        let rows = viz.rows
        let last = rows.last

        let f2 = last?.facts?["fact2"]
        let f1 = last?.facts?["fact1"]
        let f3 = last?.facts?["fact3"]

        let points = rows.compactMap { row in
            row.facts?["fact2"]?.value ?? row.facts?["fact1"]?.value
        }

        return WidgetTile(
            geoName: geo.geo_name,
            vizTitle: viz.viz_title,
            vizTimespan: viz.viz_timespan,
            vizFormat: viz.viz_format,
            reportDate: last?.report_date,
            latestValue: f2?.value ?? f1?.value,
            latestDisplay: f2?.raw ?? f1?.raw,
            fact1Label: f1?.label,
            fact1Display: f1?.raw,
            fact3Label: f3?.label,
            fact3Display: f3?.raw,
            points: points
        )
    }
}

// MARK: - Response Models

struct DashboardResponse: Decodable {
    let results: [Geo]

    struct Geo: Decodable {
        let geo_id: Int
        let geo_name: String
        let viz: [Viz]
    }

    struct Viz: Decodable {
        let viz_id: Int
        let viz_title: String
        let viz_subtitle: String?
        let viz_timespan: String?
        let viz_format: String?
        let viz_unit: String?
        let rows: [Row]
    }

    struct Row: Decodable {
        let report_date: String
        let update_date: String?
        let facts: [String: Fact]?
    }

    struct Fact: Decodable {
        let value: Double?
        let label: String?
        let exp: String?
        let raw: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decodeIfPresent(Double.self, forKey: .value)
                ?? (try c.decodeIfPresent(Int.self, forKey: .value)).map(Double.init)
                ?? (try c.decodeIfPresent(String.self, forKey: .value)).flatMap(Double.init)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            exp = try c.decodeIfPresent(String.self, forKey: .exp)
            raw = try c.decodeIfPresent(String.self, forKey: .raw)
        }

        enum CodingKeys: String, CodingKey {
            case value, label, exp, raw
        }
    }
}