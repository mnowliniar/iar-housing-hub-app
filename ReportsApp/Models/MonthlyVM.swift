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
                      let rows = viz.chart_data,
                      !rows.isEmpty else { continue }

                func parseNumber(_ raw: Any?) -> Double? {
                    switch raw {
                    case let d as Double:
                        return d
                    case let i as Int:
                        return Double(i)
                    case let s as String:
                        let cleaned = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return Double(cleaned)
                    default:
                        return nil
                    }
                }

                func firstMatchingKey(in rows: [[String: JSONValue]], candidates: [String]) -> String? {
                    candidates.first(where: { candidate in rows.contains(where: { $0[candidate] != nil }) })
                }

                func fallbackNumericKey(in rows: [[String: JSONValue]]) -> String? {
                    guard let firstRow = rows.first else { return nil }
                    let excludedKeys: Set<String> = [
                        "Reporting date", "reporting_date", "Date", "date",
                        "x", "label", "Label", "category", "Category"
                    ]
                    return firstRow.keys.first(where: { key in
                        !excludedKeys.contains(key) && rows.contains(where: { parseNumber($0[key]?.value) != nil })
                    })
                }

                let valueKey: String? = {
                    switch viz.type {
                    case "lineWeek", "barWeek":
                        return firstMatchingKey(in: rows, candidates: ["Estimated weekly value", "Actual value", "Value", "y1", "y"])
                            ?? fallbackNumericKey(in: rows)
                    case "yoyExp", "line3mo", "line12mo", "line", "lineYr":
                        return firstMatchingKey(in: rows, candidates: ["Value"])
                            ?? fallbackNumericKey(in: rows)
                    default:
                        return firstMatchingKey(in: rows, candidates: ["Value", "y", "y1"])
                            ?? fallbackNumericKey(in: rows)
                    }
                }()

                guard let resolvedValueKey = valueKey else { continue }

                let nums: [Double] = rows.compactMap { row in
                    parseNumber(row[resolvedValueKey]?.value)
                }
                pointsByLabel[title] = Array(nums.suffix(12))
            }
        }
    }
}
