import SwiftUI
import Charts
import Foundation

struct YoYMomentumPoint: Identifiable {
    let id = UUID()
    let date: Date
    let gap: Double
}

/// weekly_yoy_momentum charts the gap itself: this year minus the same
/// week last year. Dark 6-week and teal 3-week average markers show the
/// transition; the dashed zero line is "even with last year".
struct YoYMomentumInsightChartView: View {
    let points: [YoYMomentumPoint]
    let format: String?
    let unit: String?

    private var scaledPoints: [YoYMomentumPoint] {
        points.map {
            YoYMomentumPoint(
                date: $0.date,
                gap: ChartValueFormatter.scale($0.gap, format: format, unit: unit)
            )
        }
    }

    private var windowedPoints: [YoYMomentumPoint] {
        Array(scaledPoints.suffix(26))
    }

    private var lastThree: [YoYMomentumPoint] {
        Array(windowedPoints.suffix(3))
    }

    private var priorSix: [YoYMomentumPoint] {
        guard windowedPoints.count > 3 else { return [] }
        let end = windowedPoints.count - 3
        let start = max(end - 6, 0)
        return Array(windowedPoints[start..<end])
    }

    private var recentAverage: Double? {
        let vals = lastThree.map(\.gap)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var priorAverage: Double? {
        let vals = priorSix.map(\.gap)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func signedLabel(_ value: Double) -> String {
        let text = ChartValueFormatter.label(value, format: format, unit: unit)
        return value >= 0 && !text.hasPrefix("+") ? "+\(text)" : text
    }

    private var xAxisDates: [Date] {
        guard !windowedPoints.isEmpty else { return [] }
        return stride(from: 0, to: windowedPoints.count, by: 8).map { windowedPoints[$0].date }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private var yDomain: ClosedRange<Double> {
        var vals = windowedPoints.map(\.gap)
        vals.append(0)
        guard let lo = vals.min(), let hi = vals.max() else { return -1...1 }
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vs same week last year")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(windowedPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Gap", point.gap)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.gray.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                RuleMark(y: .value("Even", 0))
                    .foregroundStyle(Color.gray.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

                if let avg = priorAverage,
                   let start = priorSix.first?.date,
                   let end = priorSix.last?.date {
                    RuleMark(
                        xStart: .value("PriorStart", start),
                        xEnd: .value("PriorEnd", end),
                        y: .value("PriorAvg", avg)
                    )
                    .foregroundStyle(Color.gray.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 5, lineCap: .round))
                    .annotation(position: .top, alignment: .leading) {
                        Text("6-wk avg: \(signedLabel(avg))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let avg = recentAverage,
                   let start = lastThree.first?.date,
                   let end = lastThree.last?.date {
                    RuleMark(
                        xStart: .value("RecentStart", start),
                        xEnd: .value("RecentEnd", end),
                        y: .value("RecentAvg", avg)
                    )
                    .foregroundStyle(BrandColors.teal)
                    .lineStyle(StrokeStyle(lineWidth: 5, lineCap: .round))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("3-wk avg: \(signedLabel(avg))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrandColors.teal)
                    }
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
                            Text(signedLabel(number))
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

enum YoYMomentumInsightChartParser {
    /// Builds the gap series (value minus the value 52 weeks earlier) from
    /// the raw weekly chart data, matching the server's index arithmetic.
    static func parse(_ chartData: [[String: Any]]) -> [YoYMomentumPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var dates: [Date] = []
        var values: [Double] = []
        for row in chartData {
            guard
                let dateString = row["Reporting date"] as? String,
                let date = formatter.date(from: dateString)
            else { continue }
            let value = number(from: row["Estimated weekly value"]) ?? number(from: row["Actual value"])
            guard let value else { continue }
            dates.append(date)
            values.append(value)
        }

        guard values.count > 52 else { return [] }
        var out: [YoYMomentumPoint] = []
        for i in 52..<values.count {
            out.append(YoYMomentumPoint(date: dates[i], gap: values[i] - values[i - 52]))
        }
        return out
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
