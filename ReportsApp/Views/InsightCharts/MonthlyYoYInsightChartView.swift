//
//  MonthlyYoYPoint.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/17/26.
//

import SwiftUI
import Charts

struct MonthlyYoYPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let yoyValue: Double?
}

enum MonthlyYoYInsightChartParser {
    static func parse(_ chartData: [[String: Any]]) -> [MonthlyYoYPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        return chartData.compactMap { row in
            guard
                let dateString = row["Reporting date"] as? String,
                let date = formatter.date(from: dateString),
                let value = number(from: row["Value"] ?? row["value"] ?? row["y"] ?? row["Actual value"])
            else {
                return nil
            }

            let yoyValue = number(from: row["Value (previous year)"] ?? row["yoy"] ?? row["y2"])
            return MonthlyYoYPoint(
                date: date,
                value: value,
                yoyValue: yoyValue
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

struct MonthlyYoYInsightChartView: View {
    let points: [MonthlyYoYPoint]
    let format: String?
    let unit: String?

    private var displayPoints: [MonthlyYoYPoint] {
        Array(points.suffix(13))
    }

    private var currentValue: Double? {
        displayPoints.last?.value
    }

    private var yoyValue: Double? {
        displayPoints.last?.yoyValue
    }

    private var yValues: [Double] {
        displayPoints.flatMap { point in
            [point.value, point.yoyValue].compactMap { $0 }
        }
    }

    private var yMin: Double {
        0
    }

    private var yMax: Double {
        guard let maxVal = yValues.max() else { return 100 }
        let minVal = yValues.min() ?? maxVal
        let pad = Swift.max((maxVal - minVal) * 0.18, 1)
        return maxVal + pad
    }

    private var annotationOrder: (upper: Double?, lower: Double?) {
        guard let currentValue, let yoyValue else {
            return (currentValue, yoyValue)
        }
        return currentValue >= yoyValue
            ? (currentValue, yoyValue)
            : (yoyValue, currentValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let unit, !unit.isEmpty {
                Text(unit.prefix(1).uppercased() + unit.dropFirst())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(displayPoints.enumerated()), id: \.element.id) { index, point in
                    BarMark(
                        x: .value("MonthIndex", index),
                        y: .value("Value", point.value),
                        width: .fixed(14)
                    )
                    .foregroundStyle(BrandColors.teal.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .chartYScale(domain: yMin...yMax)
            .chartXAxis {
                AxisMarks(values: xAxisIndexes) { value in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.gray.opacity(0.25))
                    AxisValueLabel {
                        if let index = value.as(Int.self),
                           displayPoints.indices.contains(index) {
                            let date = displayPoints[index].date
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
                    .padding(.trailing, 56)
                    .padding(.bottom, 14)
                    .background(Color.clear)
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plotFrame = geo[proxy.plotAreaFrame]

                    if let currentValue,
                       let currentY = proxy.position(forY: currentValue) {
                        Path { path in
                            path.move(to: CGPoint(x: plotFrame.minX, y: currentY))
                            path.addLine(to: CGPoint(x: geo.size.width, y: currentY))
                        }
                        .stroke(BrandColors.teal, lineWidth: 2)
                    }

                    if let yoyValue,
                       let yoyY = proxy.position(forY: yoyValue) {
                        Path { path in
                            path.move(to: CGPoint(x: plotFrame.minX, y: yoyY))
                            path.addLine(to: CGPoint(x: geo.size.width, y: yoyY))
                        }
                        .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }

                    if let upper = annotationOrder.upper,
                       let upperY = proxy.position(forY: upper) {
                        Text(formatValue(upper))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(upper == currentValue ? BrandColors.teal : .secondary)
                            .position(x: geo.size.width - 18, y: upperY - 10)
                    }

                    if let lower = annotationOrder.lower,
                       let lowerY = proxy.position(forY: lower) {
                        Text(formatValue(lower))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(lower == currentValue ? BrandColors.teal : .secondary)
                            .position(x: geo.size.width - 18, y: lowerY + 10)
                    }
                }
            }
        }
    }

    private var xAxisIndexes: [Int] {
        displayPoints.enumerated().compactMap { index, _ in
            index % 4 == 0 || index == displayPoints.count - 1 ? index : nil
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func formatValue(_ value: Double) -> String {
        let rounded = value.rounded()

        if format == "$" {
            return "$" + Int(rounded).formatted()
        }

        if abs(rounded) >= 1000 {
            return Int(rounded).formatted()
        }

        if rounded == floor(rounded) {
            return String(Int(rounded))
        }

        return String(format: "%.1f", rounded)
    }
}
