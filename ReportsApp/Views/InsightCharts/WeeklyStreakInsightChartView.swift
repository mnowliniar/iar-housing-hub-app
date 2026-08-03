import SwiftUI
import Charts
import Foundation

struct WeeklyStreakPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct WeeklyStreakInsightChartView: View {
    let points: [WeeklyStreakPoint]
    let format: String?
    let unit: String?

    private var scaledPoints: [WeeklyStreakPoint] {
        points.map {
            WeeklyStreakPoint(
                date: $0.date,
                value: ChartValueFormatter.scale($0.value, format: format, unit: unit)
            )
        }
    }

    /// Trailing strict streak length, matching the server's definition.
    private var streakLength: Int {
        let values = scaledPoints.map(\.value)
        guard values.count > 1 else { return 0 }
        var up = 0
        var down = 0
        for i in stride(from: values.count - 1, through: 1, by: -1) {
            if values[i] > values[i - 1] { up += 1 } else { break }
        }
        for i in stride(from: values.count - 1, through: 1, by: -1) {
            if values[i] < values[i - 1] { down += 1 } else { break }
        }
        return max(up, down)
    }

    private var windowedPoints: [WeeklyStreakPoint] {
        let k = streakLength
        let windowLen = min(scaledPoints.count, max(k + 6, 12))
        return Array(scaledPoints.suffix(windowLen))
    }

    /// The streak run plus the point it started from, so the teal segment
    /// connects to the gray context line.
    private var streakPoints: [WeeklyStreakPoint] {
        Array(windowedPoints.suffix(streakLength + 1))
    }

    private var latestPoint: WeeklyStreakPoint? {
        windowedPoints.last
    }

    private var xAxisDates: [Date] {
        guard !windowedPoints.isEmpty else { return [] }
        return stride(from: 0, to: windowedPoints.count, by: 4).map { windowedPoints[$0].date }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private var yValues: [Double] {
        windowedPoints.map(\.value)
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

                ForEach(streakPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "streak")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(BrandColors.teal)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
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

enum WeeklyStreakInsightChartParser {
    static func parse(_ chartData: [[String: Any]]) -> [WeeklyStreakPoint] {
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

            let value = number(from: row["Estimated weekly value"]) ?? number(from: row["Actual value"])
            guard let value else { return nil }

            return WeeklyStreakPoint(date: date, value: value)
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
