import SwiftUI
import Charts
import Foundation

struct WeeklyWowPoint: Identifiable {
    let id = UUID()
    let date: Date
    let actual: Double?
    let estimated: Double?
}

struct WeeklyWowInsightChartView: View {
    let points: [WeeklyWowPoint]
    let format: String?
    let unit: String?

    private var chartPoints: [WeeklyWowPoint] {
        points.map { point in
            WeeklyWowPoint(
                date: point.date,
                actual: point.actual.map { ChartValueFormatter.scale($0, format: format, unit: unit) },
                estimated: point.estimated.map { ChartValueFormatter.scale($0, format: format, unit: unit) }
            )
        }
    }

    private var actualPoints: [WeeklyWowPoint] {
        let filtered = chartPoints.filter { $0.actual != nil }
        return Array(filtered.suffix(12))
    }

    private var latestPoint: WeeklyWowPoint? {
        actualPoints.last
    }

    private var priorSixWeekPoints: [WeeklyWowPoint] {
        guard actualPoints.count > 3 else { return [] }
        let end = max(actualPoints.count - 3, 0)
        let start = max(end - 6, 0)
        return Array(actualPoints[start..<end])
    }

    private var lastThreeWeekPoints: [WeeklyWowPoint] {
        Array(actualPoints.suffix(3))
    }

    private var priorSixWeekAverage: Double? {
        let values = priorSixWeekPoints.compactMap(\.actual)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var lastThreeWeekAverage: Double? {
        let values = lastThreeWeekPoints.compactMap(\.actual)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var xAxisDates: [Date] {
        guard !actualPoints.isEmpty else { return [] }
        return stride(from: 0, to: actualPoints.count, by: 4).map { actualPoints[$0].date }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private var yValues: [Double] {
        actualPoints.compactMap(\.actual)
    }

    private var yMin: Double {
        guard let min = yValues.min() else { return 0 }
        let pad = max((yMax - min) * 0.08, 1)
        return min - pad
    }

    private var yMax: Double {
        guard let maxVal = yValues.max() else { return 100 }
        let minVal = yValues.min() ?? maxVal
        let pad = Swift.max((maxVal - minVal) * 0.08, 1)
        return maxVal + pad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let unit, !unit.isEmpty {
                Text(unit.prefix(1).uppercased() + unit.dropFirst())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
            ForEach(actualPoints) { point in
                if let actual = point.actual {
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Actual", actual)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(BrandColors.teal)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }

            if let avg = priorSixWeekAverage,
               let start = priorSixWeekPoints.first?.date,
               let end = priorSixWeekPoints.last?.date {
                RuleMark(
                    xStart: .value("Prior6Start", start),
                    xEnd: .value("Prior6End", end),
                    y: .value("Prior6Avg", avg)
                )
                .foregroundStyle(Color.gray.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .annotation(position: .overlay, alignment: .leading) {
                    Text("6wk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.gray.opacity(0.9))
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(y: -6)
                }
            }

            if let avg = lastThreeWeekAverage,
               let start = lastThreeWeekPoints.first?.date,
               let end = lastThreeWeekPoints.last?.date {
                RuleMark(
                    xStart: .value("Last3Start", start),
                    xEnd: .value("Last3End", end),
                    y: .value("Last3Avg", avg)
                )
                .foregroundStyle(BrandColors.teal.opacity(0.9))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .annotation(position: .overlay, alignment: .leading) {
                    Text("3wk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(y: -6)
                }
            }

            if let latest = latestPoint, let actual = latest.actual {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Actual", actual)
                )
                .foregroundStyle(BrandColors.teal)
                .symbolSize(70)
            }
        }
        .chartYScale(domain: yMin...yMax)
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
                        Text(formatValue(number))
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

    private func formatValue(_ value: Double) -> String {
        ChartValueFormatter.label(value, format: format, unit: unit)
    }
}

enum WeeklyWowInsightChartParser {
    static func parse(_ chartData: [[String: Any]]) -> [WeeklyWowPoint] {
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

            let actual = number(from: row["Actual value"])
            let estimated = number(from: row["Estimated weekly value"])

            return WeeklyWowPoint(
                date: date,
                actual: estimated,
                estimated: estimated
            )
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
