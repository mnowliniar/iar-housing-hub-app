//
//  MonthlyVM.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 8/27/25.
//


import SwiftUI

@MainActor
final class MonthlyVM: ObservableObject {
    @Published var month: String = ""
    @Published var facts: [(label: String, value: String, sub: String?)] = []
    @Published var pointsByLabel: [String: [Double]] = [:]
    @Published var isLoading = false
    @AppStorage("selectedGeo") var geoID: Int = 18 // e.g. Indiana

    private func fetchCSVData(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("text/csv, text/plain, */*", forHTTPHeaderField: "Accept")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)

        let (data, _) = try await session.data(for: req)
        if data.count > 0 { return data }

        // Fallback for 0-byte bodies from some CDNs on watchOS
        let (tmpURL, _) = try await session.download(for: req)
        return try Data(contentsOf: tmpURL)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Resolve latest date via fast endpoint, then fetch the weekly report (id = 1)
        guard !Task.isCancelled else { return }
        let latestDate = try? await APIService.fetchLatestReportDate(reportID: 1, geoID: String(geoID))
        guard let updateDate = latestDate, !updateDate.isEmpty else { return }

        if let summary = await APIService.fetchReportSummary(
            reportID: 1,
            updateDate: updateDate,
            geoID: geoID
        ) {
            month = summary.report_date

            // Pick specific vizzes by title, in desired order
            let wantedOrder = ["Closed Sales", "New Listings", "Weekly Sale Price"]
            let wantedSet = Set(wantedOrder)

            // Keep only vizzes with wanted titles
            let filtered = summary.vizzes.filter { wantedSet.contains($0.title) }

            // Sort in the specified order
            let orderIndex = Dictionary(uniqueKeysWithValues: wantedOrder.enumerated().map { ($1, $0) })
            let ordered = filtered.sorted { a, b in
                (orderIndex[a.title] ?? .max) < (orderIndex[b.title] ?? .max)
            }

            // Facts: label = viz title; value = fact1 (or fact2); sub = exp1 (or exp2)
            facts = ordered.map { v in
                let label = v.title
                let value = v.fact2 ?? ""
                let sub = [v.fact3label, v.fact3].compactMap { $0 }.joined(separator: " ")
                return (label, value, sub)
            }

            // Build last-12-point mini series for each card we show
            pointsByLabel = [:]
            let titlesNeedingSeries = ["Closed Sales", "New Listings", "Weekly Sale Price"]
            for title in titlesNeedingSeries {
                guard let viz = summary.vizzes.first(where: { $0.title == title }),
                      let url = viz.csvURL else { continue }
                do {
                    let csvData = try await fetchCSVData(url)
                    guard let s = String(data: csvData, encoding: .utf8)
                       ?? String(data: csvData, encoding: .isoLatin1) else { continue }

                    // Split on CRLF or LF
                    let lines = s.contains("\r\n") ? s.split(separator: "\r\n") : s.split(separator: "\n")
                    guard let headerLine = lines.first, lines.count > 1 else { continue }
                    let header = headerLine.split(separator: ",").map(String.init)

                    // Prefer weekly columns; fall back to generic; else index 1
                    let preferred = [
                        "Estimated weekly value",
                        "Actual value",
                        "Value",
                        "y"
                    ]
                    let valueIdx: Int = (
                        header.firstIndex(where: { preferred.contains($0) })
                        ?? (header.count > 1 ? 1 : 0)
                    )

                    let rows = lines.dropFirst()
                    let nums: [Double] = rows.compactMap { line in
                        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                        guard cols.indices.contains(valueIdx) else { return nil }
                        return Double(cols[valueIdx].replacingOccurrences(of: ",", with: ""))
                    }
                    pointsByLabel[title] = Array(nums.suffix(12))
                } catch {
                    // Ignore failures for this series
                }
            }
        }
    }
}
