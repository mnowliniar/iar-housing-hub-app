import SwiftUI
import Charts
import Foundation

struct CrossingPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// Shared by weekly_crossing and monthly_crossing: the recent window with
/// the crossed round-number gridline dashed, and the post-crossing segment
/// plus endpoint in teal. The crossed line is recomputed with the server's
/// exact step logic so the chart works from bare chart data.
struct CrossingInsightChartView: View {
    let points: [CrossingPoint]
    let isMonthly: Bool
    let format: String?
    let unit: String?

    private var allValues: [Double] { points.map(\.value) }

    private var crossedLine: Double? {
        guard allValues.count >= 9 else { return nil }
        let prevStat: Double
        let curStat: Double
        if isMonthly {
            prevStat = allValues[allValues.count - 2]
            curStat = allValues[allValues.count - 1]
        } else {
            let prior3 = Array(allValues.suffix(6).prefix(3))
            let last3 = Array(allValues.suffix(3))
            prevStat = prior3.reduce(0, +) / 3.0
            curStat = last3.reduce(0, +) / 3.0
        }

        let sorted = allValues.sorted()
        let level = sorted[sorted.count / 2]
        let step: Double
        if (format ?? "").contains("%") {
            step = 0.01
        } else {
            let raw = abs(level) / 8.0
            guard raw > 0 else { return nil }
            let mag = pow(10.0, floor(log10(raw)))
            step = [1.0, 2.0, 5.0, 10.0].map { $0 * mag }.first { raw <= $0 } ?? mag
        }

        if curStat > prevStat {
            let cand = floor(curStat / step) * step
            if prevStat < cand && cand <= curStat { return cand }
        } else if curStat < prevStat {
            let cand = floor(curStat / step) * step + step
            if curStat < cand && cand <= prevStat { return cand }
        }
        return nil
    }

    private var windowedPoints: [CrossingPoint] {
        let windowLen = isMonthly ? 14 : 16
        return points.suffix(windowLen).map {
            CrossingPoint(
                date: $0.date,
                value: ChartValueFormatter.scale($0.value, format: format, unit: unit)
            )
        }
    }

    private var scaledLine: Double? {
        crossedLine.map { ChartValueFormatter.scale($0, format: format, unit: unit) }
    }

    /// Index of the first point of the segment that last crossed the line.
    private var crossIndex: Int {
        guard let line = scaledLine else { return max(windowedPoints.count - 1, 0) }
        let vals = windowedPoints.map(\.value)
        guard vals.count > 1 else { return 0 }
        for i in stride(from: vals.count - 1, through: 1, by: -1) {
            if (vals[i] < line) != (vals[i - 1] < line) {
                return i
            }
        }
        return vals.count - 1
    }

    private var tealPoints: [CrossingPoint] {
        Array(windowedPoints.suffix(windowedPoints.count - max(crossIndex - 1, 0)))
    }

    private var latestPoint: CrossingPoint? { windowedPoints.last }

    private var xAxisDates: [Date] {
        guard !windowedPoints.isEmpty else { return [] }
        return stride(from: 0, to: windowedPoints.count, by: 4).map { windowedPoints[$0].date }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = isMonthly ? "MMM ''yy" : "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private var yDomain: ClosedRange<Double> {
        var vals = windowedPoints.map(\.value)
        if let line = scaledLine { vals.append(line) }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...100 }
        let pad = max((hi - lo) * 0.12, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let unit, !unit.isEmpty {
                Text(unit.prefix(1).uppercased() + unit.dropFirst())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(windowedPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "context")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.gray.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(tealPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "crossing")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(BrandColors.teal)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                if let line = scaledLine {
                    RuleMark(y: .value("Crossed", line))
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("crossed: \(ChartValueFormatter.label(line, format: format, unit: unit))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                if let latest = latestPoint {
                    PointMark(
                        x: .value("Date", latest.date),
                        y: .value("Value", latest.value)
                    )
                    .foregroundStyle(BrandColors.teal)
                    .symbolSize(70)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.gray.opacity(0.15))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.gray.opacity(0.25))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.gray.opacity(0.15))
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.gray.opacity(0.25))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(ChartValueFormatter.label(number, format: format, unit: unit))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(Color.clear)
            }
        }
    }
}

enum CrossingInsightChartParser {
    static func parse(_ chartData: [[String: Any]]) -> [CrossingPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        return chartData.compactMap { row in
            guard
                let dateString = row["Reporting date"] as? String,
                let date = formatter.date(from: dateString)
            else {
                return nil
            }

            let value = number(from: row["Estimated weekly value"])
                ?? number(from: row["Actual value"])
                ?? number(from: row["Value"])
                ?? number(from: row["value"])
            guard let value else { return nil }

            return CrossingPoint(date: date, value: value)
        }
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        case let s as String:
            return Double(s)
        default:
            return nil
        }
    }
}
