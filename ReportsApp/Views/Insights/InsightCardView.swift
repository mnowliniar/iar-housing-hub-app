//
//  InsightCardView.swift
//  ReportsApp
//
//  The insight card, in one place: the eyebrow, the plain-English headline,
//  the chart drawn for its kind, the source line. The Market and Insights
//  pages, Home's top insight and the opened insight all draw this one, so
//  they look like one app. Tapping a card opens InsightDetailView, where
//  the chart gets the room it deserves and a swipe moves through the
//  market's insights.
//

import SwiftUI

enum InsightSupport {
    /// The kinds the app draws itself. Anything else shows the server's chart.
    static let nativeTypes: Set<String> = [
        "weekly_wow", "weekly_recent3_yoy", "weekly_trend_yoy", "weekly_elbow", "weekly_streak",
        "weekly_record", "monthly_record", "weekly_crossing", "monthly_crossing",
        "weekly_yoy_momentum", "weekly_geo_vs_state", "price_breakout_yoy", "monthly_yoy",
    ]

    static func supportsViz(_ type: String?) -> Bool {
        guard let type else { return false }
        return nativeTypes.contains(type)
    }

    static func headline(_ insight: InsightPreviewItem) -> String {
        let raw = insight.headline ?? insight.title ?? insight.viz ?? "Insight"
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    /// Chart data for the insights the app draws itself, keyed by source id.
    static func loadVizData(for insights: [InsightPreviewItem]) async -> [Int: InsightVizData] {
        var loaded: [Int: InsightVizData] = [:]
        for insight in insights {
            guard supportsViz(insight.type), let instanceID = insight.sourceID else { continue }
            if let data = await APIService.fetchInsightVizData(instanceID: instanceID, bucket: insight.bucket, insightType: insight.type) {
                loaded[instanceID] = data
            }
        }
        return loaded
    }
}

/// Which insight a tap opened.
struct InsightIndex: Identifiable {
    let id: Int
}

struct InsightCardBody: View {
    enum Style { case card, detail }

    let insight: InsightPreviewItem
    let geoName: String
    let vizData: InsightVizData?
    var style: Style = .card

    private var chartHeight: CGFloat { style == .card ? 220 : 380 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .card ? 18 : 12) {
            Text("\(insight.title ?? insight.viz ?? "Insight") • \(geoName)")
                .font(.subheadline.weight(style == .card ? .regular : .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.trailing, style == .card ? 28 : 0)

            Text(InsightSupport.headline(insight))
                .font(style == .card ? .title2.weight(.bold) : .title.weight(.bold))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(style == .card ? 3 : 6)
                .fixedSize(horizontal: false, vertical: true)

            chart
                .frame(height: chartHeight)

            Text("Source: Indiana Association of REALTORS®")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let vizData {
            nativeChart(vizData)
        } else if !InsightSupport.supportsViz(insight.type) {
            serverChart
        } else {
            InsightChartPlaceholder(insight: insight)
        }
    }

    @ViewBuilder
    private func nativeChart(_ vizData: InsightVizData) -> some View {
        let type = insight.type ?? ""
        switch type {
        case "weekly_record", "monthly_record":
            RecordInsightChartView(points: RecordInsightChartParser.parse(vizData.chartData),
                                   format: vizData.format, unit: vizData.unit)
        case "weekly_crossing", "monthly_crossing":
            CrossingInsightChartView(points: CrossingInsightChartParser.parse(vizData.chartData),
                                     isMonthly: type == "monthly_crossing",
                                     format: vizData.format, unit: vizData.unit)
        case "weekly_yoy_momentum":
            YoYMomentumInsightChartView(points: YoYMomentumInsightChartParser.parse(vizData.chartData),
                                        format: vizData.format, unit: vizData.unit)
        case "weekly_geo_vs_state":
            if let geoPct = vizData.geoPct, let statePct = vizData.statePct {
                GeoVsStateInsightChartView(geoPct: geoPct, statePct: statePct,
                                           geoLabel: insight.geo ?? "This market")
            } else {
                serverChart
            }
        case "weekly_streak":
            WeeklyStreakInsightChartView(points: WeeklyStreakInsightChartParser.parse(vizData.chartData),
                                         format: vizData.format, unit: vizData.unit)
        case "weekly_elbow":
            WeeklyElbowInsightChartView(points: WeeklyElbowInsightChartParser.parse(vizData.chartData),
                                        format: vizData.format, unit: vizData.unit)
        case "weekly_recent3_yoy":
            WeeklyRecent3YoYInsightChartView(points: WeeklyRecent3YoYInsightChartParser.parse(vizData.chartData),
                                             format: vizData.format, unit: vizData.unit)
        case "weekly_trend_yoy":
            WeeklyTrendYoYInsightChartView(points: WeeklyTrendYoYInsightChartParser.parse(vizData.chartData),
                                           format: vizData.format, unit: vizData.unit)
        case "weekly_wow":
            WeeklyWowInsightChartView(points: WeeklyWowInsightChartParser.parse(vizData.chartData),
                                      format: vizData.format, unit: vizData.unit)
        case "price_breakout_yoy":
            PriceBreakoutInsightChartView(points: PriceBreakoutInsightChartParser.parse(vizData.chartData, bucket: vizData.bucket),
                                          reportDate: insight.reportDate,
                                          format: vizData.format, unit: vizData.unit)
        case "monthly_yoy":
            MonthlyYoYInsightChartView(points: MonthlyYoYInsightChartParser.parse(vizData.chartData),
                                       format: vizData.format, unit: vizData.unit)
        default:
            serverChart
        }
    }

    /// The server's own chart. New kinds work without an app update.
    @ViewBuilder
    private var serverChart: some View {
        if let instanceID = insight.sourceID, let type = insight.type, !type.isEmpty {
            InsightWebChartView(instanceID: instanceID, insightType: type)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            InsightChartPlaceholder(insight: insight)
        }
    }
}

struct InsightChartPlaceholder: View {
    let insight: InsightPreviewItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))
            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.largeTitle)
                    .foregroundStyle(BrandColors.teal)
                Text(insight.type?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Insight chart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let unit = insight.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

/// The grey shapes shown while an insight loads.
struct InsightCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 150, height: 18)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(Color(.systemGray4)).frame(height: 22)
                RoundedRectangle(cornerRadius: 5).fill(Color(.systemGray4)).frame(width: 220, height: 22)
            }
            RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)).frame(height: 220)
            RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 220, height: 14)
        }
    }
}

// MARK: - Opened big

/// An insight with room: the headline at title size, the chart at 380
/// points, a swipe through the market's insights, Share and Ask Spark.
struct InsightDetailView: View {
    let insights: [InsightPreviewItem]
    let geoName: String
    let vizData: [Int: InsightVizData]
    @State private var index: Int
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: InsightShareItem?

    init(insights: [InsightPreviewItem], geoName: String, vizData: [Int: InsightVizData], startIndex: Int) {
        self.insights = insights
        self.geoName = geoName
        self.vizData = vizData
        _index = State(initialValue: min(max(startIndex, 0), max(insights.count - 1, 0)))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(insights.enumerated()), id: \.offset) { i, insight in
                    page(insight)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .background(HubStyle.card.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(index + 1) of \(insights.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        share(current)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this insight")
                    .disabled(insights.isEmpty)
                }
            }
        }
        .sheet(item: $shareItem, onDismiss: {
            shareItem?.cleanup()
            shareItem = nil
        }) { item in
            ActivityViewController(activityItems: [item.activityItemSource])
        }
    }

    private var current: InsightPreviewItem? {
        insights.indices.contains(index) ? insights[index] : nil
    }

    private func page(_ insight: InsightPreviewItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InsightCardBody(insight: insight,
                                geoName: insight.geo ?? geoName,
                                vizData: insight.sourceID.flatMap { vizData[$0] },
                                style: .detail)

                Button {
                    askSpark(insight)
                } label: {
                    HStack {
                        Label("Ask Spark about this", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(HubStyle.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .padding(20)
            .padding(.bottom, 28)
        }
    }

    private func askSpark(_ insight: InsightPreviewItem) {
        let place = insight.geo ?? geoName
        app.sparkPrompt = "Explain this about \(place): \(InsightSupport.headline(insight)). What's behind it, and what should I tell clients?"
        app.selectedTab = 2
        dismiss()
    }

    @MainActor
    private func share(_ insight: InsightPreviewItem?) {
        guard let insight else { return }
        let content = InsightCardBody(insight: insight,
                                      geoName: insight.geo ?? geoName,
                                      vizData: insight.sourceID.flatMap { vizData[$0] })
            .padding(20)
            .frame(width: 320, height: 400, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .preferredColorScheme(.light)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage,
           let item = InsightShareItem.make(image: image, title: InsightSupport.headline(insight)) {
            shareItem = item
            EventTracker.fire(.downloadInsightChart, metadata: [
                "viz_id": String(insight.vizID ?? 0),
                "insight_type": insight.type ?? "",
                "geo_id": String(insight.geoID ?? 0),
            ])
        }
    }
}

// MARK: - Home's insights

/// The market's insights this week as a row of cards on Home, under the
/// numbers. Tap one to open it big; the share button sends it as an image.
struct InsightRail: View {
    let geoID: String
    @State private var insights: [InsightPreviewItem] = []
    @State private var vizData: [Int: InsightVizData] = [:]
    @State private var loading = true
    @State private var opened: InsightIndex?
    @State private var shareItem: InsightShareItem?

    private let cardWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Insights") {
                NavigationLink("View all") {
                    InsightsView(geoID: Int(geoID) ?? 18)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                // Same height for every card in the row: each is willing to
                // stretch, and the row sizes itself to the tallest.
                HStack(alignment: .top, spacing: 12) {
                    if loading && insights.isEmpty {
                        ForEach(0..<2, id: \.self) { _ in
                            InsightCardSkeleton()
                                .frame(width: cardWidth - 36, alignment: .topLeading)
                                .hubCard(padding: 18)
                        }
                    } else {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            card(insight, index: index)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        .task(id: geoID) { await load() }
        .fullScreenCover(item: $opened) { item in
            InsightDetailView(insights: insights, geoName: insights.first?.geo ?? "", vizData: vizData, startIndex: item.id)
        }
        .sheet(item: $shareItem, onDismiss: {
            shareItem?.cleanup()
            shareItem = nil
        }) { item in
            ActivityViewController(activityItems: [item.activityItemSource])
        }
    }

    private func card(_ insight: InsightPreviewItem, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            InsightCardBody(insight: insight,
                            geoName: insight.geo ?? "",
                            vizData: insight.sourceID.flatMap { vizData[$0] })
                .frame(width: cardWidth - 36, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
            Button {
                share(insight)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share this insight")
        }
        .hubCard(padding: 18)
        .contentShape(Rectangle())
        .onTapGesture { opened = InsightIndex(id: index) }
    }

    private func load() async {
        loading = true
        for await list in APIService.insightPreviewStream(geoID: geoID, top: 6) {
            guard !Task.isCancelled else { return }
            insights = list
            loading = false
            vizData = await InsightSupport.loadVizData(for: list)
        }
        loading = false
    }

    @MainActor
    private func share(_ insight: InsightPreviewItem) {
        let content = InsightCardBody(insight: insight,
                                      geoName: insight.geo ?? "",
                                      vizData: insight.sourceID.flatMap { vizData[$0] })
            .padding(20)
            .frame(width: 320, height: 400, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .preferredColorScheme(.light)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage,
           let item = InsightShareItem.make(image: image, title: InsightSupport.headline(insight)) {
            shareItem = item
            EventTracker.fire(.downloadInsightChart, metadata: [
                "viz_id": String(insight.vizID ?? 0),
                "insight_type": insight.type ?? "",
                "geo_id": String(insight.geoID ?? 0),
            ])
        }
    }
}
