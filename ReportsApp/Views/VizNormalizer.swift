//
//  Series.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/11/26.
//


import Foundation

struct Series {
    let name: String
    let values: [Double]
}

struct DataPackage {
    var labels: [String] = []
    var dates: [Date]? = nil

    var values: [Double] = []
    var values2: [Double] = []
    var comparison: [Double] = []

    var expectedLow: [Double] = []
    var expectedHigh: [Double] = []

    var recentTrend: [Double] = []
    var previousTrend: [Double] = []
    var yoyRecentTrend: [Double] = []
    var yoyPreviousTrend: [Double] = []

    var series: [Series] = []
    var format: String = "default"
    var variant: String? = nil
}

enum VizRenderKind {
    case yoyExp
    case line
    case lineYoy
    case barCat
    case barGrouped
    case barWeek
    case lineComp
    case dotPlot
    case lineTrend
    case lineDaily
    case unsupported
}

enum VizNormalizer {
    static func makePackage(
        chartData: [[String: JSONValue]],
        type: String,
        format: String,
        variant: String? = nil,
        title: String? = nil
    ) -> DataPackage? {
        guard !chartData.isEmpty else { return nil }

        let labels = buildLabels(from: chartData, type: type)
        let dates = buildDates(from: chartData)

        var pkg = DataPackage()
        pkg.labels = labels
        pkg.dates = dates
        pkg.format = format.isEmpty ? "default" : format
        pkg.variant = variant

        switch renderKind(for: type) {
        case .yoyExp:
            pkg.values = numericSeries(chartData, preferredKeys: ["Value"])
            pkg.values2 = numericSeries(chartData, preferredKeys: ["Value (previous year)", "value_previous_year"])
            pkg.expectedLow = numericSeries(chartData, preferredKeys: ["expected_low"])
            pkg.expectedHigh = numericSeries(chartData, preferredKeys: ["expected_high"])

            pkg.series = [
                Series(name: "Current", values: pkg.values),
                Series(name: "Previous Year", values: pkg.values2),
                Series(name: "Expected Low", values: pkg.expectedLow),
                Series(name: "Expected High", values: pkg.expectedHigh)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .line:
            let current = numericSeries(chartData, preferredKeys: ["Estimated weekly value", "Actual value", "Value", "y1", "y"])
            pkg.values = current
            pkg.series = [Series(name: title ?? "Current", values: current)]

        case .lineYoy:
            let current = numericSeries(chartData, preferredKeys: ["Value", "y", "y1"])
            let prior = numericSeries(chartData, preferredKeys: ["Value (previous year)", "value_previous_year", "y2"])
            pkg.values = current
            pkg.values2 = prior
            pkg.series = [
                Series(name: "Current", values: current),
                Series(name: "Previous Year", values: prior)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .barCat:
            let current = numericSeries(chartData, preferredKeys: ["y"])
            //let current = numericSeries(chartData, preferredKeys: ["Value", "y", "y1"])
            pkg.values = current
            pkg.series = [Series(name: title ?? "Value", values: current)]

        case .barGrouped:
            let current = numericSeries(chartData, preferredKeys: ["y"])
            let prior = numericSeries(chartData, preferredKeys: ["y2"])
            pkg.values = current
            pkg.values2 = prior
            pkg.series = [
                Series(name: "Previous Year", values: prior),
                Series(name: "Current Year", values: current)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .barWeek:
            let current = numericSeries(chartData, preferredKeys: ["Estimated weekly value", "Actual value", "Value", "y"])
            pkg.values = current
            pkg.series = [Series(name: title ?? "Value", values: current)]

        case .lineComp:
            let current = numericSeries(chartData, preferredKeys: ["Value (This Area)", "Value (Selected Area)", "Value", "y"])
            let comp = numericSeries(chartData, preferredKeys: ["Value (Indiana)", "Comparison", "y2"])
            pkg.values = current
            pkg.comparison = comp
            pkg.series = [
                Series(name: "Selected Area", values: current),
                Series(name: "Comparison", values: comp)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .dotPlot:
            let current = numericSeries(chartData, preferredKeys: ["y"])
            let comp = numericSeries(chartData, preferredKeys: ["y2"])
            pkg.values = current
            pkg.comparison = comp
            pkg.series = [
                Series(name: "Current Year", values: current),
                Series(name: "Previous Year", values: comp)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .lineTrend:
            let base = numericSeries(chartData, preferredKeys: ["Estimated weekly value", "Value", "y1", "y"])
            pkg.values = base
            pkg.recentTrend = windowAverageLine(base, startOffset: 3, endOffset: 0)
            pkg.previousTrend = windowAverageLine(base, startOffset: 9, endOffset: 3)
            pkg.yoyRecentTrend = windowAverageLine(base, startOffset: 55, endOffset: 52)
            pkg.yoyPreviousTrend = windowAverageLine(base, startOffset: 61, endOffset: 55)
            pkg.series = [
                Series(name: "Weekly", values: base),
                Series(name: "Recent Average", values: pkg.recentTrend),
                Series(name: "Previous Average", values: pkg.previousTrend),
                Series(name: "3-week avg", values: pkg.yoyRecentTrend),
                Series(name: "6-week avg", values: pkg.yoyPreviousTrend)
            ].filter { !$0.values.allSatisfy(\.isNaN) }

        case .lineDaily:
            let current = numericSeries(chartData, preferredKeys: ["Value", "y", "y1"])
            pkg.values = current
            pkg.series = [Series(name: title ?? "Value", values: current)]

        case .unsupported:
            let fallback = numericSeries(chartData, preferredKeys: [])
            guard !fallback.isEmpty else { return nil }
            pkg.values = fallback
            pkg.series = [Series(name: title ?? "Value", values: fallback)]
        }

        return pkg
    }

    static func renderKind(for type: String) -> VizRenderKind {
        switch type {
        case "yoyExp":
            return .yoyExp
        case "line", "lineWeek", "lineYr":
            return .line
        case "lineYoy", "line12mo", "line3mo":
            return .lineYoy
        case "barCat":
            return .barCat
        case "barGrouped":
            return .barGrouped
        case "barWeek":
            return .barWeek
        case "lineComp":
            return .lineComp
        case "dotPlot":
            return .dotPlot
        case "lineTrend":
            return .lineTrend
        case "lineDaily":
            return .lineDaily
        default:
            return .unsupported
        }
    }

    private static func parseNumber(_ raw: Any?) -> Double? {
        switch raw {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let s as String:
            let cleaned = s
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        default:
            return nil
        }
    }

    private static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let s as String:
            return s
        case let d as Double:
            return String(d)
        case let i as Int:
            return String(i)
        case let b as Bool:
            return String(b)
        default:
            return nil
        }
    }

    private static func valueAt(_ row: [String: JSONValue], _ key: String) -> Any? {
        row[key]?.value
    }

    private static func firstMatchingKey(
        in rows: [[String: JSONValue]],
        candidates: [String]
    ) -> String? {
        candidates.first(where: { candidate in
            rows.contains(where: { $0[candidate] != nil })
        })
    }

    private static func fallbackNumericKey(in rows: [[String: JSONValue]]) -> String? {
        guard let firstRow = rows.first else { return nil }
        let excludedKeys: Set<String> = [
            "Reporting date", "reporting_date", "Date", "date",
            "x", "label", "Label", "category", "Category"
        ]

        return firstRow.keys.first(where: { key in
            !excludedKeys.contains(key) &&
            rows.contains(where: { parseNumber($0[key]?.value) != nil })
        })
    }

    private static func numericSeries(
        _ rows: [[String: JSONValue]],
        preferredKeys: [String]
    ) -> [Double] {
        let key = firstMatchingKey(in: rows, candidates: preferredKeys) ?? fallbackNumericKey(in: rows)
        guard let resolvedKey = key else { return [] }

        return rows.map { row in
            parseNumber(valueAt(row, resolvedKey)) ?? .nan
        }
    }

    private static func buildLabels(from rows: [[String: JSONValue]], type: String) -> [String] {
        let labelKey = firstMatchingKey(
            in: rows,
            candidates: ["x", "label", "Label", "category", "Category", "Reporting date", "reporting_date", "Date", "date"]
        )

        guard let key = labelKey else {
            return rows.indices.map { String($0 + 1) }
        }

        return rows.map { row in
            let raw = stringValue(valueAt(row, key)) ?? ""
            if key == "Reporting date" || key == "reporting_date" || key == "Date" || key == "date" {
                return formatDateLabel(raw, type: type)
            }
            return raw
        }
    }

    private static func buildDates(from rows: [[String: JSONValue]]) -> [Date]? {
        let dateKey = firstMatchingKey(
            in: rows,
            candidates: ["Reporting date", "reporting_date", "Date", "date"]
        )
        guard let key = dateKey else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let dates = rows.compactMap { row -> Date? in
            guard let raw = stringValue(valueAt(row, key)) else { return nil }
            return df.date(from: raw)
        }

        return dates.isEmpty ? nil : dates
    }

    private static func formatDateLabel(_ raw: String, type: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        guard let date = df.date(from: raw) else { return raw }

        let out = DateFormatter()
        switch type {
        case "lineDaily":
            out.dateFormat = "MMM d"
        case "lineWeek", "barWeek", "lineTrend":
            out.dateFormat = "MMM d"
        default:
            out.dateFormat = "MMM yyyy"
        }
        return out.string(from: date)
    }

    private static func windowAverageLine(_ values: [Double], startOffset: Int, endOffset: Int) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }

        let start = max(0, n - startOffset)
        let end = max(0, n - endOffset)
        guard start < end else { return Array(repeating: .nan, count: n) }

        let slice = values[start..<end].filter { !$0.isNaN }
        guard !slice.isEmpty else { return Array(repeating: .nan, count: n) }

        let avg = slice.reduce(0, +) / Double(slice.count)
        var line = Array(repeating: Double.nan, count: n)
        for i in start..<end {
            line[i] = avg
        }
        return line
    }
}
