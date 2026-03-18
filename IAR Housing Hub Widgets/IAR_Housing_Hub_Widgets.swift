//
//  HousingHubEntry.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import WidgetKit
import SwiftUI

struct HousingHubEntry: TimelineEntry {
    let date: Date
    let tile: WidgetTile?
}

struct HousingHubInsightEntry: TimelineEntry {
    let date: Date
    let payload: InsightWidgetPayload?
}

struct WidgetTile: Decodable {
    let geoName: String
    let vizTitle: String
    let vizTimespan: String?
    let vizFormat: String?
    let reportDate: String?
    let latestValue: Double?
    let latestDisplay: String?
    let fact1Label: String?
    let fact1Display: String?
    let fact3Label: String?
    let fact3Display: String?
    let points: [Double]
}

struct HousingHubProvider: AppIntentTimelineProvider {
    typealias Intent = HousingHubWidgetIntent

    func placeholder(in context: Context) -> HousingHubEntry {
        HousingHubEntry(date: Date(), tile: nil)
    }

    func snapshot(for configuration: HousingHubWidgetIntent, in context: Context) async -> HousingHubEntry {
        let geoID = configuration.geo?.id ?? "18"
        let vizID = configuration.indicator?.id ?? "25"
        let tile = await WidgetAPI.fetchTile(geoID: geoID, vizID: vizID)
        return HousingHubEntry(date: Date(), tile: tile)
    }

    func timeline(for configuration: HousingHubWidgetIntent, in context: Context) async -> Timeline<HousingHubEntry> {
        let geoID = configuration.geo?.id ?? "18"
        let vizID = configuration.indicator?.id ?? "25"
        let tile = await WidgetAPI.fetchTile(geoID: geoID, vizID: vizID)

        let entry = HousingHubEntry(date: Date(), tile: tile)
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)

        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct HousingHubInsightProvider: AppIntentTimelineProvider {
    typealias Intent = HousingHubInsightWidgetIntent

    func placeholder(in context: Context) -> HousingHubInsightEntry {
        HousingHubInsightEntry(
            date: Date(),
            payload: InsightWidgetPayload(
                geoName: "Marion County",
                items: [
                    InsightWidgetItem(headline: "Recent weeks up 30% vs 6-week trend", direction: "up", geoID: 18097, geo: "Marion County", sourceID: 22084237, type: "weekly_wow", reportDate: "Week of Mar. 02, 2026", viz: "Weekly pendings"),
                    InsightWidgetItem(headline: "$150K-$249K range down 3% YOY", direction: "down", geoID: 18097, geo: "Marion County", sourceID: 22053988, type: "price_breakout_yoy", reportDate: "February 2026", viz: "Weekly pendings"),
                    InsightWidgetItem(headline: "up 17% YOY", direction: "up", geoID: 18097, geo: "Marion County", sourceID: 21396410, type: "monthly_yoy", reportDate: "February 2026", viz: "Weekly pendings")
                ]
            )
        )
    }

    func snapshot(for configuration: HousingHubInsightWidgetIntent, in context: Context) async -> HousingHubInsightEntry {
        let geoID = configuration.geo?.id ?? "18"
        let payload = await WidgetAPI.fetchInsightPayload(geoID: geoID, top: 3)
        return HousingHubInsightEntry(date: .now, payload: payload)
    }

    func timeline(for configuration: HousingHubInsightWidgetIntent, in context: Context) async -> Timeline<HousingHubInsightEntry> {
        let geoID = configuration.geo?.id ?? "18"
        let payload = await WidgetAPI.fetchInsightPayload(geoID: geoID, top: 15)

        guard let payload, !payload.items.isEmpty else {
            let entry = HousingHubInsightEntry(date: .now, payload: nil)
            return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600)))
        }

        let shuffled = payload.items.shuffled()
        let doubled = shuffled + shuffled
        var entries: [HousingHubInsightEntry] = []

        for hourOffset in 0..<3 {
            let start = min(hourOffset, max(shuffled.count - 1, 0))
            let end = min(start + min(4, shuffled.count), doubled.count)
            let items = Array(doubled[start..<end])
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: .now) ?? .now
            entries.append(
                HousingHubInsightEntry(
                    date: entryDate,
                    payload: InsightWidgetPayload(geoName: payload.geoName, items: items)
                )
            )
        }

        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3 * 3600)))
    }
}

struct HousingHubWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HousingHubProvider.Entry

    var body: some View {
        if let tile = entry.tile {
            switch family {
            case .systemSmall:
                SmallTileView(tile: tile)
                    .widgetURL(URL(string: "iarhousinghub://"))
            case .systemMedium:
                MediumTileView(tile: tile)
                    .widgetURL(URL(string: "iarhousinghub://"))
            case .systemLarge:
                LargeTileView(tile: tile)
                    .widgetURL(URL(string: "iarhousinghub://"))
            default:
                SmallTileView(tile: tile)
                    .widgetURL(URL(string: "iarhousinghub://"))
            }
        } else {
            WidgetEmptyView()
        }
    }
}

struct HousingHubInsightWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HousingHubInsightProvider.Entry

    var body: some View {
        if let payload = entry.payload {
            let geoID = payload.items.first?.geoID ?? 18

            switch family {
            case .systemSmall:
                InsightSmallTileView(payload: payload)
                    .widgetURL(URL(string: "iarhousinghub://market/\(geoID)/insights"))
            case .systemMedium:
                InsightMediumTileView(payload: payload)
                    .widgetURL(URL(string: "iarhousinghub://market/\(geoID)/insights"))
            case .systemLarge:
                InsightLargeTileView(payload: payload)
                    .widgetURL(URL(string: "iarhousinghub://market/\(geoID)/insights"))
            default:
                InsightSmallTileView(payload: payload)
                    .widgetURL(URL(string: "iarhousinghub://market/\(geoID)/insights"))
            }
        } else {
            WidgetEmptyView()
        }
    }
}

struct HousingHubWidget: Widget {
    let kind: String = "HousingHubWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HousingHubWidgetIntent.self,
            provider: HousingHubProvider()
        ) { entry in
            HousingHubWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Housing Hub")
        .description("Track a market indicator at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HousingHubInsightWidget: Widget {
    let kind: String = "HousingHubInsightWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HousingHubInsightWidgetIntent.self,
            provider: HousingHubInsightProvider()
        ) { entry in
            HousingHubInsightWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Housing Hub Insights")
        .description("Top market insights at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    HousingHubWidget()
} timeline: {
    HousingHubEntry(
        date: .now,
        tile: WidgetTile(
            geoName: "Marion County",
            vizTitle: "Inventory",
            vizTimespan: "Week",
            vizFormat: "",
            reportDate: "Week of Mar. 02, 2026",
            latestValue: 648.9,
            latestDisplay: "649",
            fact1Label: "vs previous period",
            fact1Display: "12",
            fact3Label: "YOY",
            fact3Display: "+8%",
            points: [520, 529, 548, 563, 572, 594, 611, 641, 657, 690, 695, 714]
        )
    )
}
