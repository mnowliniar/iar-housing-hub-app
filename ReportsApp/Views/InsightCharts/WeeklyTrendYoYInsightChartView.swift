//
//  WeeklyTrendYoYInsightChartPoint.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 4/16/26.
//


//
//  WeeklyTrendYoYInsightChartView.swift
//  ReportsApp
//

import SwiftUI
import Charts
import Foundation

struct WeeklyTrendYoYInsightChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct WeeklyTrendYoYSegmentPoint: Identifiable {
    let id = UUID()
    let segment: String
    let date: Date
    let value: Double
}

enum WeeklyTrendYoYInsightChartParser {
    static func parse(_ raw: [[String: Any]]) -> [WeeklyTrendYoYInsightChartPoint] {
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
            return WeeklyTrendYoYInsightChartPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }
}

struct WeeklyTrendYoYInsightChartView: View {
    let points: [WeeklyTrendYoYInsightChartPoint]
    let format: String?
    let unit: String?

    private var chartPoints: [WeeklyTrendYoYInsightChartPoint] {
        points.map { point in
            WeeklyTrendYoYInsightChartPoint(
                date: point.date,
                value: ChartValueFormatter.scale(point.value, format: format, unit: unit)
            )
        }
    }

    private var sortedPoints: [WeeklyTrendYoYInsightChartPoint] {
        chartPoints.sorted { $0.date < $1.date }
    }

    private var displayedPoints: [WeeklyTrendYoYInsightChartPoint] {
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

    private var currentWindow: [WeeklyTrendYoYInsightChartPoint] {
        guard displayedPoints.count >= 9 else { return [] }
        return Array(displayedPoints.suffix(9))
    }

    private var priorYearWindow: [WeeklyTrendYoYInsightChartPoint] {
        guard displayedPoints.count >= 61 else { return [] }
        return Array(displayedPoints[0...8])
    }

    private var currentWindowPoints: [WeeklyTrendYoYSegmentPoint] {
        currentWindow.map {
            WeeklyTrendYoYSegmentPoint(segment: "thisYear9wk", date: $0.date, value: $0.value)
        }
    }

    private var priorYearWindowPoints: [WeeklyTrendYoYSegmentPoint] {
        priorYearWindow.map {
            WeeklyTrendYoYSegmentPoint(segment: "lastYear9wk", date: $0.date, value: $0.value)
        }
    }

    var body: some View {
        let stroke = BrandColors.teal
        let mutedLine = Color.secondary.opacity(0.22)
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

            ForEach(priorYearWindowPoints) { point in
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

            ForEach(currentWindowPoints) { point in
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

            if let priorAnchor = priorYearWindow.first {
                PointMark(
                    x: .value("Date", priorAnchor.date),
                    y: .value("Value", priorAnchor.value)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text("Last year")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(labelColor)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(x: 8, y: -4)
                }
            }

            if let currentAnchor = currentWindow.first {
                PointMark(
                    x: .value("Date", currentAnchor.date),
                    y: .value("Value", currentAnchor.value)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text("This year")
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
