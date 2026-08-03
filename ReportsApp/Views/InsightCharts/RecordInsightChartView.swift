import SwiftUI
import Charts
import Foundation

struct RecordPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// Shared by weekly_record and monthly_record: the full multi-year series
/// in gray, the prior extreme as a dashed reference line, and the teal
/// endpoint breaking through it.
struct RecordInsightChartView: View {
    let points: [RecordPoint]
    let format: String?
    let unit: String?

    private var scaledPoints: [RecordPoint] {
        points.map {
            RecordPoint(
                date: $0.date,
                value: ChartValueFormatter.scale($0.value, format: format, unit: unit)
            )
        }
    }

    private var values: [Double] { scaledPoints.map(\.value) }

    private var isHigh: Bool {
        guard let cur = values.last else { return true }
        let prior = values.dropLast()
        return cur > (prior.max() ?? cur)
    }

    private var referenceValue: Double? {
        let prior = values.dropLast()
        return isHigh ? prior.max() : prior.min()
    }

    private var referencePoint: RecordPoint? {
        guard let ref = referenceValue else { return nil }
        return scaledPoints.dropLast().first { $0.value == ref }
    }

    private var latestPoint: RecordPoint? { scaledPoints.last }

    private var xAxisDates: [Date] {
        guard scaledPoints.count > 1 else { return scaledPoints.map(\.date) }
        let step = max(scaledPoints.count / 3, 1)
        return stride(from: 0, to: scaledPoints.count, by: step).map { scaledPoints[$0].date }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM ''yy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private var yMin: Double {
        guard let min = values.min() else { return 0 }
        let pad = max((yMaxRaw - min) * 0.08, 1)
        return min - pad
    }

    private var yMax: Double {
        yMaxRaw + max((yMaxRaw - (values.min() ?? yMaxRaw)) * 0.08, 1)
    }

    private var yMaxRaw: Double {
        values.max() ?? 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let unit, !unit.isEmpty {
                Text(unit.prefix(1).uppercased() + unit.dropFirst())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(scaledPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.gray.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                if let ref = referenceValue {
                    RuleMark(y: .value("Reference", ref))
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("\(isHigh ? "previous high" : "previous low"): \(ChartValueFormatter.label(ref, format: format, unit: unit))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                if let refPoint = referencePoint {
                    PointMark(
                        x: .value("Date", refPoint.date),
                        y: .value("Value", refPoint.value)
                    )
                    .foregroundStyle(Color.gray.opacity(0.8))
                    .symbolSize(40)
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

enum RecordInsightChartParser {
    static func parse(_ chartData: [[String: Any]]) -> [RecordPoint] {
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

            return RecordPoint(date: date, value: value)
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
