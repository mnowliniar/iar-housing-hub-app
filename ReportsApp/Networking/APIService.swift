import Foundation

struct LatestDateResponse: Decodable {
    let reportId: Int
    let geoId: String?
    let date: String
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
