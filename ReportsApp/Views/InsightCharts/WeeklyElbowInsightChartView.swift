//
//  WeeklyElbowInsightChartView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 4/16/26.
//



import SwiftUI
import Charts
import Foundation

struct WeeklyElbowInsightChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum WeeklyElbowInsightChartParser {
    static func parse(_ raw: [[String: Any]]) -> [WeeklyElbowInsightChartPoint] {
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
            return WeeklyElbowInsightChartPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }
}

struct WeeklyElbowInsightChartView: View {
    let points: [WeeklyElbowInsightChartPoint]
    let format: String?
    let unit: String?

    private struct RegressionSegment {
        let label: String
        let startDate: Date
        let endDate: Date
        let startY: Double
        let endY: Double
        let annotationDate: Date
        let annotationY: Double
    }

    private struct RegressionPoint: Identifiable {
        let id = UUID()
        let segmentLabel: String
        let date: Date
        let value: Double
    }

    private var sortedPoints: [WeeklyElbowInsightChartPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var displayedPoints: [WeeklyElbowInsightChartPoint] {
        Array(sortedPoints.suffix(12))
    }

    private var chartPoints: [WeeklyElbowInsightChartPoint] {
        displayedPoints.map { point in
            WeeklyElbowInsightChartPoint(
                date: point.date,
                value: ChartValueFormatter.scale(point.value, format: format, unit: unit)
            )
        }
    }

    private var yValues: [Double] {
        chartPoints.map(\.value)
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

    private var priorSegment: RegressionSegment? {
        guard chartPoints.count >= 9 else {
            return regressionSegment(for: Array(chartPoints.dropLast(min(3, chartPoints.count))), label: "6wk")
        }

        let startIndex = max(chartPoints.count - 9, 0)
        let endIndex = max(chartPoints.count - 3, 0)
        let segment = Array(chartPoints[startIndex..<endIndex])
        return regressionSegment(for: segment, label: "6wk")
    }

    private var recentSegment: RegressionSegment? {
        let recent = Array(chartPoints.suffix(3))
        return regressionSegment(for: recent, label: "3wk")
    }

    private var priorLinePoints: [RegressionPoint] {
        guard let segment = priorSegment else { return [] }
        return [
            RegressionPoint(segmentLabel: segment.label, date: segment.startDate, value: segment.startY),
            RegressionPoint(segmentLabel: segment.label, date: segment.endDate, value: segment.endY)
        ]
    }

    private var recentLinePoints: [RegressionPoint] {
        guard let segment = recentSegment else { return [] }
        return [
            RegressionPoint(segmentLabel: segment.label, date: segment.startDate, value: segment.startY),
            RegressionPoint(segmentLabel: segment.label, date: segment.endDate, value: segment.endY)
        ]
    }

    private func regressionSegment(
        for segmentPoints: [WeeklyElbowInsightChartPoint],
        label: String
    ) -> RegressionSegment? {
        guard segmentPoints.count >= 2 else { return nil }

        let xs = segmentPoints.indices.map { Double($0) }
        let ys = segmentPoints.map(\.value)
        let count = Double(segmentPoints.count)

        let xMean = xs.reduce(0, +) / count
        let yMean = ys.reduce(0, +) / count

        let denom = xs.reduce(0.0) { partial, x in
            partial + pow(x - xMean, 2)
        }

        let slope: Double
        if denom == 0 {
            slope = 0
        } else {
            slope = zip(xs, ys).reduce(0.0) { partial, pair in
                partial + ((pair.0 - xMean) * (pair.1 - yMean))
            } / denom
        }

        let intercept = yMean - (slope * xMean)
        let endLocalIndex = segmentPoints.count - 1
        let annotationLocalIndex = 0

        let startY = intercept
        let endY = intercept + (slope * Double(endLocalIndex))
        let annotationY = intercept + (slope * Double(annotationLocalIndex))

        guard let startDate = segmentPoints.first?.date,
              let endDate = segmentPoints.last?.date,
              let annotationDate = segmentPoints[annotationLocalIndex].date as Date? else {
            return nil
        }

        return RegressionSegment(
            label: label,
            startDate: startDate,
            endDate: endDate,
            startY: startY,
            endY: endY,
            annotationDate: annotationDate,
            annotationY: annotationY
        )
    }

    var body: some View {
        let stroke = BrandColors.teal
        let grid = Color.secondary.opacity(0.12)
        let mutedLine = Color.secondary.opacity(0.55)
        let labelColor = Color.secondary

        Chart {
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
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

            ForEach(priorLinePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segmentLabel)
                )
                .foregroundStyle(mutedLine)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round
                    )
                )
            }

            ForEach(recentLinePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segmentLabel)
                )
                .foregroundStyle(stroke)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round
                    )
                )
            }

            if let prior = priorSegment {
                PointMark(
                    x: .value("Date", prior.startDate),
                    y: .value("Value", prior.startY)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text(prior.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(labelColor)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(x: 10, y: 0)
                }
            }

            if let recent = recentSegment {
                PointMark(
                    x: .value("Date", recent.startDate),
                    y: .value("Value", recent.startY)
                )
                .foregroundStyle(.clear)
                .annotation(position: .topLeading, alignment: .leading) {
                    Text(recent.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .shadow(color: Color(.systemBackground), radius: 2, x: 0, y: 0)
                        .offset(x: 10, y: 0)
                }
            }
        }
        .chartYScale(domain: yRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(grid)
                AxisTick().foregroundStyle(grid)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
