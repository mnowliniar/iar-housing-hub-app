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
    let id: UUID = UUID()
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
    let geoPct: Double?
    let statePct: Double?
}

struct APIService {
    static let baseURL = URL(string: "https://data.indianarealtors.com/app/reports/")!

    static func fetchReportsGrouped() async -> [String: [Report]] {
        let reports = await HubCache.value(baseURL, family: .catalog, as: [Report].self) ?? []
        return Dictionary(grouping: reports, by: { $0.category })
    }

    /// Cached list first, then the Hub's when the catalog changed.
    static func reportsGroupedStream() -> AsyncStream<[String: [Report]]> {
        HubCache.stream(baseURL, family: .catalog) { data in
            let reports = try JSONDecoder().decode([Report].self, from: data)
            return Dictionary(grouping: reports, by: { $0.category })
        }
    }
    
    static func fetchGeoTypes() async -> [String] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geotypes/") else { return [] }
        return await HubCache.value(url, family: .catalog, as: [String].self) ?? []
    }

    static func fetchGeos(ofType type: String) async -> [Geo] {
        guard let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.indianarealtors.com/app/geos/?type=\(encodedType)") else { return [] }
        return await HubCache.value(url, family: .catalog, as: [Geo].self) ?? []
    }

    static func fetchGeo(geoid: String) async -> Geo? {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geo/\(geoid)") else { return nil }

        return await HubCache.value(url, family: .catalog, as: [Geo].self)?.first
    }
    
    static func fetchInsightPreview(geoID: String, top: Int = 5) async -> [InsightPreviewItem] {
        var components = URLComponents(string: "https://data.indianarealtors.com/reports/insights/preview/")!
        components.queryItems = [
            URLQueryItem(name: "geo_id", value: geoID),
            URLQueryItem(name: "top", value: String(top))
        ]

        guard let url = components.url else { return [] }
        return await HubCache.value(url, family: .data, as: InsightPreviewResponse.self)?.results ?? []
    }

    /// Cached insights first, then this week's when the data moved.
    static func insightPreviewStream(geoID: String, top: Int = 5) -> AsyncStream<[InsightPreviewItem]> {
        var components = URLComponents(string: "https://data.indianarealtors.com/reports/insights/preview/")!
        components.queryItems = [
            URLQueryItem(name: "geo_id", value: geoID),
            URLQueryItem(name: "top", value: String(top))
        ]
        guard let url = components.url else { return AsyncStream { $0.finish() } }
        return HubCache.stream(url, family: .data) { data in
            try JSONDecoder().decode(InsightPreviewResponse.self, from: data).results
        }
    }
    
    static func fetchInsightVizData(instanceID: Int, bucket: String? = nil, insightType: String? = nil) async -> InsightVizData? {
        var components = URLComponents(string: "https://data.indianarealtors.com/app/insight_viz/\(instanceID)/")!
        var queryParts: [String] = []
        if let bucket, !bucket.isEmpty {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            let encodedBucket = bucket.addingPercentEncoding(withAllowedCharacters: allowed) ?? bucket
            queryParts.append("bucket=\(encodedBucket)")
        }
        if let insightType, !insightType.isEmpty {
            queryParts.append("insight_type=\(insightType)")
        }
        if !queryParts.isEmpty {
            components.percentEncodedQuery = queryParts.joined(separator: "&")
        }

        guard let url = components.url else { return nil }
        guard let data = await HubCache.data(url, family: .data),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            debugLog("❌ Error fetching insight viz data for", instanceID)
            return nil
        }
        return InsightVizData(
            chartData: json["chart_data"] as? [[String: Any]] ?? [],
            bucket: json["bucket"] as? String,
            unit: json["unit"] as? String,
            format: json["format"] as? String,
            geoPct: json["geo_pct"] as? Double,
            statePct: json["state_pct"] as? Double
        )
    }
    
    static func fetchReportDates(reportID: Int) async -> [ReportDate] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/reports/\(reportID)/dates/") else { return [] }
        return await HubCache.value(url, family: .data, as: [ReportDate].self) ?? []
    }
    
    static func fetchReportSummary(reportID: Int, updateDate: String, geoID: Int) async -> ReportSummary? {
        let comps = updateDate.split(separator: "-")  // "2025-08-07"
        guard comps.count == 3 else { return nil }

        let urlString = "https://data.indianarealtors.com/app/reports/\(reportID)/\(comps[0])/\(comps[1])/\(comps[2])/\(geoID)/"

        guard let url = URL(string: urlString) else { return nil }
        return await HubCache.value(url, family: .data, as: ReportSummary.self)
    }
    
    static func fetchLatestReportDate(reportID: Int, geoID: String) async throws -> String {
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/reports/\(reportID)/latest-date")!
        comps.queryItems = [URLQueryItem(name: "geo", value: geoID)]
        guard let data = await HubCache.data(comps.url!, family: .data) else {
            throw URLError(.cannotLoadFromNetwork)
        }
        return try JSONDecoder().decode(LatestDateResponse.self, from: data).date
    }

    static func fetchDigest() async -> DigestResponse? {
        guard let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty else {
            return nil
        }
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/digest/")!
        comps.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        guard let url = comps.url else { return nil }
        debugLog("[Digest] requesting:", url)
        do {
            let (data, _) = try await URLSession.shared.data(for: .app(url))
            if let raw = String(data: data, encoding: .utf8) {
                debugLog("[Digest] raw response:", raw.prefix(200))
            }
            return try JSONDecoder().decode(DigestResponse.self, from: data)
        } catch {
            debugLog("❌ Error fetching digest: \(error)")
            return nil
        }
    }

    static func toggleDigestSubscription(geoID: String, reportID: Int, proptype: String) async -> Bool {
        guard let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty else {
            return false
        }
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/digest/subscribe/")!
        comps.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        guard let url = comps.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "geo_id": geoID,
            "report_id": reportID,
            "proptype": proptype
        ])
        do {
            let (data, _) = try await URLSession.shared.data(for: request.withAppIdentity())
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["subscribed"] as? Bool ?? false
        } catch {
            debugLog("❌ Error toggling digest subscription: \(error)")
            return false
        }
    }
}
