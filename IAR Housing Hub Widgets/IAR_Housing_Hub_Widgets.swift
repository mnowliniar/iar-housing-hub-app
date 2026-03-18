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

struct HousingHubProvider: TimelineProvider {
    func placeholder(in context: Context) -> HousingHubEntry {
        HousingHubEntry(
            date: Date(),
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

    func getSnapshot(in context: Context, completion: @escaping (HousingHubEntry) -> Void) {
        Task {
            let tile = await WidgetAPI.fetchTile()
            completion(HousingHubEntry(date: Date(), tile: tile))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HousingHubEntry>) -> Void) {
        Task {
            let tile = await WidgetAPI.fetchTile()
            let entry = HousingHubEntry(date: Date(), tile: tile)
            let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
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

struct HousingHubWidget: Widget {
    let kind: String = "HousingHubWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HousingHubProvider()) { entry in
            HousingHubWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Housing Hub")
        .description("Track a market indicator at a glance.")
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
