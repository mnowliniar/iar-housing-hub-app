import Foundation

struct LatestDateResponse: Decodable {
    let reportId: Int
    let geoId: String?
    let date: String
}

struct InsightPreviewResponse: Decodable {
    let geoID: Int?
    let geoName: String?
    let top: Int?
    let results: [InsightPreviewItem]

    enum CodingKeys: String, CodingKey {
        case geoID = "geo_id"
        case geoName = "geo_name"
        case top
        case results
    }
}
struct InsightPreviewItem: Decodable, Identifiable {
    let score: Double?
    let type: String?
    let geoID: Int?
    let geo: String?
    let vizID: Int?
    let viz: String?
    let title: String?
    let proptype: String?
    let updateDateOnly: String?
    let reportDate: String?
    let value: Double?
    let prevValue: Double?
    let valueFmt: String?
    let prevValueFmt: String?
    let delta: Double?
    let direction: String?
    let z: Double?
    let sigma: Double?
    let bucket: String?
    let headline: String?
    let change: String?
    let unit: String?
    let format: String?
    let sourceID: Int?

    var id: String {
        sourceID.map(String.init) ?? headline ?? title ?? viz ?? geo ?? UUID().uuidString
    }

    enum CodingKeys: String, CodingKey {
        case score
        case type
        case geoID = "geo_id"
        case geo
        case vizID = "viz_id"
        case viz
        case title
        case proptype
        case updateDateOnly = "update_date_only"
        case reportDate = "report_date"
        case value
        case prevValue = "prev_value"
        case valueFmt = "value_fmt"
        case prevValueFmt = "prev_value_fmt"
        case delta
        case direction
        case z
        case sigma
        case bucket
        case headline
        case change
        case unit
        case format
        case sourceID = "source_id"
    }
}

struct InsightVizData {
    let chartData: [[String: Any]]
    let bucket: String?
    let unit: String?
    let format: String?
}

struct APIService {
    static let baseURL = URL(string: "https://data.indianarealtors.com/app/reports/")!

    static func fetchReportsGrouped() async -> [String: [Report]] {
        do {
            let (data, _) = try await URLSession.shared.data(from: baseURL)
            let reports = try JSONDecoder().decode([Report].self, from: data)
            return Dictionary(grouping: reports, by: { $0.category })
        } catch {
            print("Failed to fetch reports: \(error)")
            return [:]
        }
    }
    
    static func fetchGeoTypes() async -> [String] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geotypes/") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("❌ Error fetching geo types: \(error)")
            return []
        }
    }

    static func fetchGeos(ofType type: String) async -> [Geo] {
        guard let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.indianarealtors.com/app/geos/?type=\(encodedType)") else { return [] }
        do {
            print("Fetch geos from url: \(url)")
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([Geo].self, from: data)
        } catch {
            print("❌ Error fetching geos: \(error)")
            return []
        }
    }

    static func fetchGeo(geoid: String) async -> Geo? {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geo/\(geoid)") else { return nil }

        do {
            print("Fetch geo from url: \(url)")
            let (data, _) = try await URLSession.shared.data(from: url)

            if let raw = String(data: data, encoding: .utf8) {
                print("[Geo] raw response:", raw)
            }

            let decoded = try JSONDecoder().decode([Geo].self, from: data)
            return decoded.first
        } catch {
            print("❌ Error fetching geo:", error)
            return nil
        }
    }
    
    static func fetchInsightPreview(geoID: String, top: Int = 5) async -> [InsightPreviewItem] {
        var components = URLComponents(string: "https://data.indianarealtors.com/reports/insights/preview/")!
        components.queryItems = [
            URLQueryItem(name: "geo_id", value: geoID),
            URLQueryItem(name: "top", value: String(top))
        ]

        guard let url = components.url else { return [] }
        print("[InsightPreview] requesting:", url)

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let raw = String(data: data, encoding: .utf8) {
                print("[InsightPreview] raw response:", raw)
            }
            let decoded = try JSONDecoder().decode(InsightPreviewResponse.self, from: data)
            print("[InsightPreview] decoded results count:", decoded.results.count)
            for r in decoded.results {
                print("[InsightPreview] item -> source_id:", r.sourceID ?? -1, "type:", r.type ?? "nil", "bucket:", r.bucket ?? "nil")
            }
            return decoded.results
        } catch {
            print("❌ Error fetching insight preview: \(error)")
            return []
        }
    }
    
    static func fetchInsightVizData(instanceID: Int, bucket: String? = nil) async -> InsightVizData? {
        var components = URLComponents(string: "https://data.indianarealtors.com/app/insight_viz/\(instanceID)/")!
        if let bucket, !bucket.isEmpty {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            let encodedBucket = bucket.addingPercentEncoding(withAllowedCharacters: allowed) ?? bucket
            components.percentEncodedQuery = "bucket=\(encodedBucket)"
        }

        guard let url = components.url else { return nil }
        print("[InsightViz] requesting:", url)

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let raw = String(data: data, encoding: .utf8) {
                print("[InsightViz] raw response:", raw)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Error fetching insight viz data: response was not an object")
                return nil
            }

            let chartData = json["chart_data"] as? [[String: Any]] ?? []
            let bucket = json["bucket"] as? String
            let unit = json["unit"] as? String
            let format = json["format"] as? String

            print("[InsightViz] parsed -> instance:", instanceID)
            print("[InsightViz] bucket:", bucket ?? "nil")
            print("[InsightViz] unit:", unit ?? "nil")
            print("[InsightViz] format:", format ?? "nil")
            print("[InsightViz] chart rows:", chartData.count)

            return InsightVizData(
                chartData: chartData,
                bucket: bucket,
                unit: unit,
                format: format
            )
        } catch {
            print("❌ Error fetching insight viz data: \(error)")
            return nil
        }
    }
    
    static func fetchReportDates(reportID: Int) async -> [ReportDate] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/reports/\(reportID)/dates/") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([ReportDate].self, from: data)
        } catch {
            print("❌ Error fetching report dates: \(error)")
            return []
        }
    }
    
    static func fetchReportSummary(reportID: Int, updateDate: String, geoID: Int) async -> ReportSummary? {
        let comps = updateDate.split(separator: "-")  // "2025-08-07"
        guard comps.count == 3 else { return nil }

        let urlString = "https://data.indianarealtors.com/app/reports/\(reportID)/\(comps[0])/\(comps[1])/\(comps[2])/\(geoID)/"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(ReportSummary.self, from: data)
        } catch {
            print("❌ Error fetching report summary: \(error)")
            return nil
        }
    }
    
    static func fetchLatestReportDate(reportID: Int, geoID: String) async throws -> String {
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/reports/\(reportID)/latest-date")!
        comps.queryItems = [URLQueryItem(name: "geo", value: geoID)]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded = try JSONDecoder().decode(LatestDateResponse.self, from: data)
        return decoded.date
    }
}
