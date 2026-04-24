

//
//  WeeklyRecent3YoYInsightChartView.swift
//  ReportsApp
//

import SwiftUI
import Charts
import Foundation

struct WeeklyRecent3YoYInsightChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct WeeklyRecent3YoYSegmentPoint: Identifiable {
    let id = UUID()
    let segment: String
    let date: Date
    let value: Double
}

enum WeeklyRecent3YoYInsightChartParser {
    static func parse(_ raw: [[String: Any]]) -> [WeeklyRecent3YoYInsightChartPoint] {
        let iso = ISO8601DateFormatter()
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd"

        return raw.compactMap { row in
            guard let rawDate = (row["Reporting date"] as? String) ?? (row["Reporting Date"] as? String),
                  let date = iso.date(from: rawDate) ?? fallback.date(from: rawDate) else {
                return nil
            }

            let rawValue = row["Estimated weekly value"] ?? row["Actual value"] ?? row["Value"] ?? row["value"]
            let value: Double?
            if let number = rawValue as? Double {
                value = number
            } else if let intValue = rawValue as? Int {
                value = Double(intValue)
            } else if let stringValue = rawValue as? String {
                value = Double(
                    stringValue
                        .replacingOccurrences(of: ",", with: "")
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                value = nil
            }

            guard let value else { return nil }
            return WeeklyRecent3YoYInsightChartPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }
}

struct WeeklyRecent3YoYInsightChartView: View {
    let points: [WeeklyRecent3YoYInsightChartPoint]
    let format: String?
    let unit: String?

    private var chartPoints: [WeeklyRecent3YoYInsightChartPoint] {
        points.map { point in
            WeeklyRecent3YoYInsightChartPoint(
                date: point.date,
                value: ChartValueFormatter.scale(point.value, format: format, unit: unit)
            )
        }
    }

    private var sortedPoints: [WeeklyRecent3YoYInsightChartPoint] {
        chartPoints.sorted { $0.date < $1.date }
    }

    private var displayedPoints: [WeeklyRecent3YoYInsightChartPoint] {
        Array(sortedPoints.suffix(61))
    }

    private var yValues: [Double] {
        displayedPoints.map(\.value)
    }

    private var yRange: ClosedRange<Double> {
        guard let minVal = yValues.min(), let maxVal = yValues.max() else {
            return 0...1
        }

        if abs(maxVal - minVal) < 0.0001 {
            let pad = max(abs(maxVal) * 0.1, 1.0)
            return (minVal - pad)...(maxVal + pad)
        }

        let pad = max((maxVal - minVal) * 0.08, 1.0)
        return (minVal - pad)...(maxVal + pad)
    }

    private var currentSegment: [WeeklyRecent3YoYInsightChartPoint] {
        guard displayedPoints.count >= 3 else { return [] }
        return Array(displayedPoints.suffix(3))
    }

    private var currentSegmentPoints: [WeeklyRecent3YoYSegmentPoint] {
        currentSegment.map {
            WeeklyRecent3YoYSegmentPoint(segment: "current3wk", date: $0.date, value: $0.value)
        }
    }

    private var priorYearSegmentPoints: [WeeklyRecent3YoYSegmentPoint] {
        priorYearSegment.map {
            WeeklyRecent3YoYSegmentPoint(segment: "priorYear3wk", date: $0.date, value: $0.value)
        }
    }

    private var priorYearSegment: [WeeklyRecent3YoYInsightChartPoint] {
        guard displayedPoints.count >= 61 else { return [] }
        return Array(displayedPoints[6...8])
    }

    var body: some View {
        let stroke = BrandColors.teal
        let mutedLine = Color.secondary.opacity(0.25)
        let priorYearStroke = Color.secondary.opacity(0.6)
        let grid = Color.secondary.opacity(0.12)
        let labelColor = Color.secondary

        Chart {
            ForEach(displayedPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(mutedLine)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            ForEach(priorYearSegmentPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segment)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(priorYearStroke)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            ForEach(currentSegmentPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segment)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(stroke)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 3.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if let priorAnchor = priorYearSegment.first {
                PointMark(
                    x: .value("Date", priorAnchor.date),
                    y: .value("Value", priorAnchor.value)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text("PY 3wk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(labelColor)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(x: 8, y: -4)
                }
            }

            if let currentAnchor = currentSegment.first {
                PointMark(
                    x: .value("Date", currentAnchor.date),
                    y: .value("Value", currentAnchor.value)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text("3wk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stroke)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(x: 8, y: -4)
                }
            }
        }
        .chartYScale(domain: yRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(grid)
                AxisTick().foregroundStyle(grid)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .foregroundStyle(labelColor)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(grid)
                AxisTick().foregroundStyle(grid)
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(chartLabel(for: doubleValue))
                            .foregroundStyle(labelColor)
                    }
                }
            }
        }
    }

    private func chartLabel(for value: Double) -> String {
        ChartValueFormatter.label(value, format: format, unit: unit)
    }
}
