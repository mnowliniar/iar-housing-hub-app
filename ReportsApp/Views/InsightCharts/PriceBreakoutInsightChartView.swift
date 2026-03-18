//
//  PriceBreakoutPoint.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/17/26.
//


import SwiftUI

struct PriceBreakoutPoint: Identifiable {
    let id = UUID()
    let label: String
    let current: Double
    let previous: Double
    let isHighlighted: Bool
}

enum PriceBreakoutInsightChartParser {
    static func parse(_ chartData: [[String: Any]], bucket: String?) -> [PriceBreakoutPoint] {
        chartData.compactMap { row in
            let label =
                (row["Price range"] as? String) ??
                (row["x"] as? String) ??
                ""

            guard
                !label.isEmpty,
                let current = number(from: row["y"] ?? row["value"]),
                let previous = number(from: row["y2"] ?? row["yoy"])
            else {
                return nil
            }

            let isHighlighted = bucket == nil ? false : (label == bucket)

            return PriceBreakoutPoint(
                label: label,
                current: current,
                previous: previous,
                isHighlighted: isHighlighted
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

struct PriceBreakoutInsightChartView: View {
    let points: [PriceBreakoutPoint]
    let reportDate: String?
    let format: String?
    let unit: String?

    private var xMin: Double {
        let minValue = points
            .flatMap { [$0.current, $0.previous] }
            .min() ?? 0
        return minValue * 0.9
    }

    private var xMax: Double {
        let maxValue = points
            .flatMap { [$0.current, $0.previous] }
            .max() ?? 100
        return maxValue * 1.12
    }

    private var hasNegativeHighlightedChange: Bool {
        points.contains { point in
            point.isHighlighted && ((point.current / point.previous) - 1) * 100 < 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                legendDot(isFilled: true)
                Text(reportDate ?? "Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                legendDot(isFilled: false)
                Text("Previous year")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let leftLabelWidth: CGFloat = 92
                let plotSpacing: CGFloat = 12
                let leftValuePadding: CGFloat = hasNegativeHighlightedChange ? 52 : 0
                let rightValuePadding: CGFloat = hasNegativeHighlightedChange ? 12 : 52
                let plotWidth = max(geo.size.width - leftLabelWidth - plotSpacing - leftValuePadding - rightValuePadding, 10)

                ZStack(alignment: .topLeading) {
                    // Grid + axis labels
                    ForEach(axisValues(), id: \.self) { tick in
                        let x = leftLabelWidth + plotSpacing + leftValuePadding + CGFloat((tick - xMin) / (xMax - xMin)) * plotWidth

                        Path { path in
                            path.move(to: CGPoint(x: x, y: 24))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height - 8))
                        }
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)

                        Text(formatValue(tick))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .position(x: x, y: 5)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(points) { point in
                            rowView(
                                point: point,
                                plotWidth: plotWidth,
                                leftLabelWidth: leftLabelWidth,
                                plotSpacing: plotSpacing,
                                leftValuePadding: leftValuePadding,
                                rightValuePadding: rightValuePadding
                            )
                        }
                    }
                    .padding(.top, 28)
                }
            }
        }
    }

    private func rowView(point: PriceBreakoutPoint, plotWidth: CGFloat, leftLabelWidth: CGFloat, plotSpacing: CGFloat, leftValuePadding: CGFloat, rightValuePadding: CGFloat) -> some View {
        let plotOriginX = leftValuePadding
        let currentX = plotOriginX + CGFloat((point.current - xMin) / (xMax - xMin)) * plotWidth
        let previousX = plotOriginX + CGFloat((point.previous - xMin) / (xMax - xMin)) * plotWidth
        let highlight = point.isHighlighted
        let pct = calculatedPercentChange(for: point)
        let isNegative = (pct ?? 0) < 0

        return HStack(alignment: .center, spacing: plotSpacing) {
            Text(point.label)
                .font(.caption)
                .foregroundStyle(highlight ? BrandColors.teal : .secondary)
                .fontWeight(highlight ? .semibold : .regular)
                .frame(width: leftLabelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                if highlight {
                    Path { path in
                        path.move(to: CGPoint(x: previousX + (isNegative ? -5 : 5), y: 11))
                        path.addLine(to: CGPoint(x: currentX, y: 11))
                    }
                    .stroke(BrandColors.teal.opacity(0.5), lineWidth: 3)
                }

                Circle()
                    .fill(highlight ? BrandColors.teal.opacity(0.5) : Color.gray.opacity(0.25))
                    .frame(width: 10, height: 10)
                    .offset(x: previousX - 5, y: 0)

                Circle()
                    .fill(highlight ? BrandColors.teal : Color.gray.opacity(0.6))
                    .frame(width: highlight ? 12 : 10, height: highlight ? 12 : 10)
                    .offset(x: currentX - (highlight ? 6 : 5), y: 0)
                if highlight, let pct {
                    Text(formattedPercent(pct))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                        .frame(width: 44, alignment: isNegative ? .trailing : .leading)
                        .offset(x: isNegative ? currentX - 50 : currentX + 10, y: 0)
                }
            }
            .frame(width: leftValuePadding + plotWidth + rightValuePadding, height: 22, alignment: .leading)
        }
    }

    private func legendDot(isFilled: Bool) -> some View {
        Circle()
            .stroke(Color.gray.opacity(0.4), lineWidth: 1.5)
            .background(
                Circle().fill(isFilled ? Color.gray.opacity(0.6) : Color.gray.opacity(0.25))
            )
            .frame(width: 8, height: 8)
    }

    private func axisValues() -> [Double] {
        let rawMin = xMin
        let rawMax = xMax
        let span = max(rawMax - rawMin, 1)
        let rawStep = span / 3
        let niceStep = niceAxisStep(for: rawStep)

        let start = floor(rawMin / niceStep) * niceStep
        return [start, start + niceStep, start + niceStep * 2, start + niceStep * 3]
    }

    private func niceAxisStep(for rawStep: Double) -> Double {
        guard rawStep > 0 else { return 1 }

        let magnitude = pow(10.0, floor(log10(rawStep)))
        let normalized = rawStep / magnitude

        let niceNormalized: Double
        if normalized <= 1 {
            niceNormalized = 1
        } else if normalized <= 2 {
            niceNormalized = 2
        } else if normalized <= 2.5 {
            niceNormalized = 2.5
        } else if normalized <= 5 {
            niceNormalized = 5
        } else {
            niceNormalized = 10
        }

        return niceNormalized * magnitude
    }

    private func formatValue(_ value: Double) -> String {
        let rounded = Int(value.rounded())

        if format == "$" {
            return "$" + rounded.formatted()
        }

        return rounded.formatted()
    }

    private func calculatedPercentChange(for point: PriceBreakoutPoint) -> Double? {
        guard point.previous != 0 else { return nil }
        let pct = ((point.current / point.previous) - 1) * 100
        return pct.rounded()
    }

    private func formattedPercent(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole >= 0 ? "+\(whole)%" : "\(whole)%"
    }
}
