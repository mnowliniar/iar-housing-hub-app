//
//  WatchComplication.swift
//  IAR Housing Hub Watch Widgets
//
//  One market number on the face: the member picks the market and the
//  indicator when adding the complication, the same way as the iPhone
//  widget. Thursday mornings, when the week's numbers post, it tells the
//  Smart Stack it is worth a look.
//

import WidgetKit
import SwiftUI

struct WatchTileEntry: TimelineEntry {
    let date: Date
    let tile: WidgetTile?
}

struct WatchTileProvider: AppIntentTimelineProvider {
    typealias Intent = HousingHubWidgetIntent
    typealias Entry = WatchTileEntry

    static let sample = WidgetTile(
        geoName: "Hamilton County", vizTitle: "Median Sale Price", vizTimespan: "Month", vizFormat: "$",
        reportDate: "September 2026", latestValue: 412_500, latestDisplay: "$412,500",
        fact1Label: nil, fact1Display: nil, fact3Label: "year over year", fact3Display: "+4%",
        points: [388, 390, 396, 401, 399, 405, 409, 404, 410, 414, 411, 412])

    func placeholder(in context: Context) -> WatchTileEntry {
        WatchTileEntry(date: .now, tile: Self.sample)
    }

    func snapshot(for configuration: HousingHubWidgetIntent, in context: Context) async -> WatchTileEntry {
        if context.isPreview { return placeholder(in: context) }
        let tile = await WidgetAPI.fetchTile(geoID: configuration.geo?.id ?? "18",
                                             vizID: configuration.indicator?.id ?? "10")
        return WatchTileEntry(date: .now, tile: tile ?? Self.sample)
    }

    func timeline(for configuration: HousingHubWidgetIntent, in context: Context) async -> Timeline<WatchTileEntry> {
        let tile = await WidgetAPI.fetchTile(geoID: configuration.geo?.id ?? "18",
                                             vizID: configuration.indicator?.id ?? "10")
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now.addingTimeInterval(3 * 3600)
        return Timeline(entries: [WatchTileEntry(date: .now, tile: tile)], policy: .after(next))
    }

    /// The watch face can't configure a widget the way the phone can; it
    /// offers this list instead. Indiana with the four numbers people watch.
    func recommendations() -> [AppIntentRecommendation<HousingHubWidgetIntent>] {
        let indicators: [(id: String, title: String, subtitle: String)] = [
            ("10", "Median Sale Price", "Median monthly sale price"),
            ("6", "Inventory", "Average daily inventory"),
            ("9", "Median Days on Market", "Days from listing to pending"),
            ("3", "Closed Sales", "Weekly total of closed sales"),
        ]
        return indicators.map { item in
            let intent = HousingHubWidgetIntent()
            intent.geoType = .state
            intent.geo = GeoEntity(id: "18", name: "Indiana", type: "State")
            intent.indicator = IndicatorEntity(id: item.id, title: item.title, subtitle: item.subtitle)
            return AppIntentRecommendation(intent: intent, description: "Indiana · \(item.title)")
        }
    }

    /// Thursday mornings: the weekly numbers land overnight, so the Smart
    /// Stack can bring the complication up when it is new.
    func relevances() async -> WidgetRelevance<HousingHubWidgetIntent> {
        var attributes: [WidgetRelevanceAttribute<HousingHubWidgetIntent>] = []
        for (start, end) in Self.thursdayMornings(count: 4) {
            attributes.append(WidgetRelevanceAttribute(configuration: HousingHubWidgetIntent(),
                                                       context: .date(from: start, to: end)))
        }
        return WidgetRelevance(attributes)
    }

    static func thursdayMornings(count: Int) -> [(Date, Date)] {
        var out: [(Date, Date)] = []
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        while out.count < count {
            if cal.component(.weekday, from: day) == 5,
               let start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: day),
               let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day),
               end > .now {
                out.append((start, end))
            }
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return out
    }
}

// MARK: - Views

struct WatchTileView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchTileEntry

    var body: some View {
        if let tile = entry.tile {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(Self.compact(tile))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        if let change = tile.fact3Display, !change.isEmpty {
                            Text(change)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(3)
                }
                .widgetLabel { Text(tile.geoName) }
            case .accessoryCorner:
                Text(Self.compact(tile))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .widgetLabel {
                        Text("\(Self.shortName(tile.geoName)) · \(tile.vizTitle)")
                    }
            case .accessoryInline:
                Text("\(Self.shortName(tile.geoName)) \(Self.compact(tile)) \(tile.fact3Display ?? "")")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.geoName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(tile.latestDisplay ?? Self.compact(tile))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if let change = tile.fact3Display, !change.isEmpty {
                            Text(change)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .center) {
                        Text(tile.vizTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        WatchSparkline(points: tile.points)
                            .frame(width: 44, height: 12)
                    }
                }
            }
        } else {
            Text("Housing Hub")
                .font(.caption2)
        }
    }

    /// "$412,500" reads as "$413K" in a circle.
    static func compact(_ tile: WidgetTile) -> String {
        let display = tile.latestDisplay ?? ""
        guard let value = tile.latestValue else { return display }
        let prefix = display.hasPrefix("$") ? "$" : ""
        let suffix = display.hasSuffix("%") ? "%" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return prefix + String(format: "%.1fM", value / 1_000_000) + suffix
        }
        if magnitude >= 10_000 {
            return prefix + String(format: "%.0fK", value / 1_000) + suffix
        }
        if display.count <= 7 { return display }
        return prefix + String(format: "%.0f", value) + suffix
    }

    /// "Hamilton County" → "Hamilton Co."
    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " County", with: " Co.")
            .replacingOccurrences(of: " (Association)", with: "")
            .replacingOccurrences(of: " (MLS)", with: "")
    }
}

struct WatchSparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard points.count > 1, let lo = points.min(), let hi = points.max() else { return }
                let span = max(hi - lo, 1)
                for (i, v) in points.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(points.count - 1)
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct HousingHubComplication: Widget {
    let kind = "HousingHubComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: HousingHubWidgetIntent.self, provider: WatchTileProvider()) { entry in
            WatchTileView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "iarhousinghub://"))
        }
        .configurationDisplayName("Housing Hub")
        .description("One market number on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
