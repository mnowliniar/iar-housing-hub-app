//
//  SmallTileView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//

import SwiftUI

private let widgetTeal = Color(red: 0/255, green: 115/255, blue: 126/255)

struct SmallTileView: View {
    let tile: WidgetTile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            Text(tile.geoName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(tile.vizTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                Text(display)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            

            MiniSparkline(
                points: tile.points,
                trendLabel: tile.vizTimespan.map { "12-\($0.lowercased()) trend" }
            )
            .padding(.top, 0)

        }
    }
}

struct MediumTileView: View {
    let tile: WidgetTile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            Text(reportLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(tile.vizTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            
            HStack(spacing: 4) {
                if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                    Text(display)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let fact = tile.fact1Display {
                    HStack(spacing: 4) {
                        Text(fact)
                            .font(.caption)
                            .bold()

                        if let label = tile.fact1Label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            MiniSparkline(
                points: tile.points,
                trendLabel: tile.vizTimespan.map { "12-\($0.lowercased()) trend" }
            )

        }
    }

    private var reportLine: String {
        if let reportDate = tile.reportDate {
            return "\(reportDate) • \(tile.geoName)"
        }
        return tile.geoName
    }
}

struct LargeTileView: View {
    let tile: WidgetTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            Text(reportLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(tile.vizTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                Text(display)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            
            HStack(spacing: 4) {
                if let fact = tile.fact1Display {
                    HStack(spacing: 4) {
                        Text(fact)
                            .font(.caption)
                            .bold()

                        if let label = tile.fact1Label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if let fact3 = tile.fact3Display, !fact3.isEmpty {
                    HStack(spacing: 4) {
                        Spacer()
                        Text(fact3)
                            .font(.caption)
                            .bold()

                        if let label = tile.fact3Label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            

            MiniSparkline(
                points: tile.points,
                trendLabel: tile.vizTimespan.map { "12-\($0.lowercased()) trend" }
            )
                .frame(maxHeight: .infinity)
        }
    }

    private var reportLine: String {
        if let reportDate = tile.reportDate {
            return "\(reportDate) • \(tile.geoName)"
        }
        return tile.geoName
    }
}

private func formatValue(_ value: Double, format: String?) -> String {
    switch format {
    case "$":
        return "$" + Int(value.rounded()).formatted()
    case "%":
        if value.rounded() == value {
            return "\(Int(value))%"
        } else {
            return String(format: "%.1f%%", value)
        }
    default:
        if value.rounded() == value {
            return Int(value).formatted()
        } else {
            return String(format: "%.1f", value)
        }
    }
}


struct WidgetEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Housing Hub")
                .font(.headline)
            Text("No data available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct InsightSmallTileView: View {
    let payload: InsightWidgetPayload

    var body: some View {
        let item = payload.items.first

        VStack(alignment: .leading, spacing: 2) {
            Text(payload.geoName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let item {
                Text(item.viz ?? "Insight")
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer(minLength: 0)

            if let item {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.direction == "down" ? "▼" : "▲")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(item.direction == "down" ? .secondary : widgetTeal)

                        Text(item.headline.capitalizingFirstLetter)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }

                    if let reportDate = item.reportDate {
                        Text(reportDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 18)
                    }
                }
            } else {
                Text("No insights available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InsightMediumTileView: View {
    let payload: InsightWidgetPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(payload.geoName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if payload.items.isEmpty {
                Text("No insights available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(payload.items.prefix(2), id: \ .headline) { item in
                    VStack(alignment: .leading, spacing: 4) {

                        HStack(alignment: .top, spacing: 8) {
                            Text(item.viz ?? "Insight")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Spacer()
                            if let reportDate = item.reportDate {
                                Text(reportDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text(item.direction == "down" ? "▼" : "▲")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(item.direction == "down" ? .secondary : widgetTeal)

                            Text(item.headline.capitalizingFirstLetter)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
        }
    }
}

struct InsightLargeTileView: View {
    let payload: InsightWidgetPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(payload.geoName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Insights and Trends").fontWeight(.semibold)
            Spacer()
            
            if payload.items.isEmpty {
                Text("No insights available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    
                    ForEach(payload.items.prefix(5), id: \ .headline) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            
                            Divider()
                                .opacity(0.5)
                                .padding(.top, 4)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.viz ?? "Insight")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.direction == "down" ? "▼" : "▲")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(item.direction == "down" ? .secondary : widgetTeal)
                                
                                Text(item.headline.capitalizingFirstLetter)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                                
                            if let reportDate = item.reportDate {
                                Text(reportDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.trailing, 8)
            }
            
        }
    }
}

extension String {
    var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
