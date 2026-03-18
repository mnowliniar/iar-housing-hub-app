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
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.vizTitle)
                .font(.headline)
                .lineLimit(1)

            Text(tile.geoName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                Text(display)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            MiniSparkline(points: tile.points)

            if let timespan = tile.vizTimespan, !timespan.isEmpty {
                Text("12-\(timespan.lowercased()) trend")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}

struct MediumTileView: View {
    let tile: WidgetTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tile.vizTitle)
                .font(.headline)
                .lineLimit(1)

            Text(reportLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .top, spacing: 8) {
                if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                    Text(display)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let fact = tile.fact1Display {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fact)
                            .font(.subheadline.bold())

                        if let label = tile.fact1Label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            MiniSparkline(points: tile.points)

            if let timespan = tile.vizTimespan, !timespan.isEmpty {
                Text("12-\(timespan.lowercased()) trend")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
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
            Text(tile.vizTitle)
                .font(.headline)
                .lineLimit(1)

            Text(reportLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .top, spacing: 8) {
                if let display = tile.latestDisplay ?? tile.latestValue.map { formatValue($0, format: tile.vizFormat) } {
                    Text(display)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let fact = tile.fact1Display {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fact)
                            .font(.subheadline.bold())

                        if let label = tile.fact1Label {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if let fact3 = tile.fact3Display, !fact3.isEmpty {
                HStack(spacing: 4) {
                    Text(fact3)
                        .font(.caption.bold())

                    if let label = tile.fact3Label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            MiniSparkline(points: tile.points)
                .frame(maxHeight: .infinity)

            if let timespan = tile.vizTimespan, !timespan.isEmpty {
                Text("12-\(timespan.lowercased()) trend")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
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
