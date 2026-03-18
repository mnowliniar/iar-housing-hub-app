//
//  WidgetAPI.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import Foundation

enum WidgetAPI {
    // Change these defaults as needed
    static let proptype = "all"

    static func fetchInsightPayload(geoID: String, top: Int = 3) async -> InsightWidgetPayload? {
        var components = URLComponents(string: "https://data.indianarealtors.com/reports/insights/preview/")!
        components.queryItems = [
            URLQueryItem(name: "geo_id", value: geoID),
            URLQueryItem(name: "top", value: String(top))
        ]

        guard let url = components.url else { return nil }

        do {
            print("[InsightWidget] requesting:", url)

            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse {
                print("[InsightWidget] status:", http.statusCode)
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("[InsightWidget] raw response:", raw)
            }

            let decoded = try JSONDecoder().decode(InsightPreviewResponse.self, from: data)

            let geoName = decoded.results.first?.geo ?? "Insights"

            return InsightWidgetPayload(
                geoName: geoName,
                items: decoded.results
            )
        } catch {
            print("❌ Error fetching insight preview:", error)
            return nil
        }
    }

    static func fetchTile(geoID: String, vizID: String) async -> WidgetTile? {
        guard let url = makeURL(geoID: geoID, vizID: vizID) else { return nil }

        do {
            print("[Widget] requesting:", url)

            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse {
                print("[Widget] status:", http.statusCode)
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("[Widget] raw response:", raw)
            }

            let decoded = try JSONDecoder().decode(DashboardResponse.self, from: data)
            print("[Widget] decoded geo count:", decoded.results.count)

            return decoded.results.first.flatMap(mapGeo)
        } catch {
            print("[Widget] fetch error:", error)
            return nil
        }
    }

    private static func makeURL(geoID: String, vizID: String) -> URL? {
        var comps = URLComponents(string: "https://data.indianarealtors.com/api/viz_set/proptype/\(proptype)")
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
            let raw = row.facts?["fact2"]?.value ?? row.facts?["fact1"]?.value
            return raw.flatMap(parseNumericString)
        }
        return WidgetTile(
            geoName: geo.geo_name,
            vizTitle: viz.viz_title,
            vizTimespan: viz.viz_timespan,
            vizFormat: viz.viz_format,
            reportDate: last?.report_date,
            latestValue: (f2?.value ?? f1?.value).flatMap(parseNumericString),
            latestDisplay: f2?.value ?? f1?.value,
            fact1Label: f1?.label,
            fact1Display: f1?.value,
            fact3Label: f3?.label,
            fact3Display: f3?.value,
            points: points
        )
    }
    
    private static func parseNumericString(_ s: String) -> Double? {
        let cleaned = s
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
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
        let value: String?
        let label: String?
        let exp: String?
        let raw: String?
    }
}

// MARK: - Insight Preview Models

struct InsightPreviewResponse: Decodable {
    let results: [InsightWidgetItem]
}

struct InsightWidgetPayload: Hashable {
    let geoName: String
    let items: [InsightWidgetItem]
}

struct InsightWidgetItem: Decodable, Hashable {
    let headline: String
    let direction: String?
    let geoID: Int
    let geo: String
    let sourceID: Int?
    let type: String?
    let reportDate: String?
    let viz: String?

    enum CodingKeys: String, CodingKey {
        case headline, direction, geo, type
        case geoID = "geo_id"
        case sourceID = "source_id"
        case reportDate = "report_date"
        case viz = "viz"
    }
}
