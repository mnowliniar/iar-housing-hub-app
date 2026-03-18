//
//  MarketView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/17/26.
//

import SwiftUI
import UIKit
import Charts

struct MarketView: View {
    let geoID: Int
    @EnvironmentObject var app: AppState
    @State private var showGeoPicker = false
    @State private var activeGeo: Geo?
    @State private var isLoadingGeo = false
    @State private var insights: [InsightPreviewItem] = []
    @State private var isLoadingInsights = false
    @State private var insightVizDataByID: [Int: InsightVizData] = [:]
    @State private var shareItem: InsightShareItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Text("Your key indicators")
                    .font(.headline)
                    .padding(.horizontal, 16)

                MarketDashboardSection(geoID: String(geoID))

                HStack {
                    Text("Insights")
                        .font(.headline)

                    Spacer()

                    NavigationLink {
                        InsightsView(geoID: geoID)
                    } label: {
                        Text("View all")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                insightsSection

                Text("Ask Spark")
                    .font(.headline)
                    .padding(.horizontal, 16)

                chatLaunchersSection
                    .padding(.bottom, 28)
            }
        }
        .background(
            LinearGradient(
                colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCurrentGeo()
            await loadInsights()
            await loadInsightVizData()
        }
        .onChange(of: geoID) { _, _ in
            Task {
                await loadCurrentGeo()
                await loadInsights()
                await loadInsightVizData()
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item.image])
        }
        .sheet(isPresented: $showGeoPicker) {
            GeoPickerSheet { newGeoID in
                app.selectedGeoID = newGeoID
                app.saveUserPrefs()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(activeGeo?.displayName ?? "Market")
                .font(.largeTitle.bold())

            HStack(spacing: 6) {
                Text(activeGeo?.type ?? "Loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.secondary)

                Text(householdText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            

            Button("Change market") {
                showGeoPicker = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var insightsSection: some View {
        Group {
            if isLoadingInsights && insights.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            insightSkeletonCard
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else if insights.isEmpty {
                Text("No insights available for this market yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(insights.prefix(5)) { insight in
                            insightCard(insight)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var chatLaunchersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chatLauncherItems, id: \.title) { item in
                if let url = chatURL(query: item.query) {
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: item.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)

                            Text(item.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }

            if let startChatURL = chatURL(query: startChatQuery) {
                Link(destination: startChatURL) {
                    HStack {
                        Text("Start Chat")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "message")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    private var chatLauncherItems: [(title: String, systemImage: String, query: String)] {
        let marketName = activeGeo?.displayName ?? "this market"
        let marketID = activeGeo?.geoid ?? geoID
        let marketRef = "\(marketName) (id:\(marketID))"

        return [
            ("What’s the latest market update?", "newspaper", "What is the latest market update in \(marketRef)"),
            ("How are prices trending?", "dollarsign", "How are sale and listing prices trending in \(marketRef)"),
            ("What is inventory like?", "house", "Detail inventory trends and price breakouts in \(marketRef)"),
            ("Chart days on market over time.", "chart.line.uptrend.xyaxis", "Make a chart of days on market in \(marketRef) over 24 months"),
            ("Draft market update email.", "envelope", "Draft a market update email for \(marketRef)"),
            ("Draft post about this market.", "number", "Draft a social media post about \(marketRef) and make an interesting chart to include")
        ]
    }

    private var startChatQuery: String {
        let marketName = activeGeo?.displayName ?? "this market"
        let marketID = activeGeo?.geoid ?? geoID
        let marketRef = "\(marketName) (id:\(marketID))"
        return "I want to chat about the real estate market in \(marketRef) Reply with a brief paragraph no chart or table and follow up with helpful questions"
    }

    private func chatURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "iarhousinghub"
        components.host = "spark"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    private var insightSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 150, height: 18)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray4))
                    .frame(height: 22)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray4))
                    .frame(width: 220, height: 22)
            }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 220)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 220, height: 14)
        }
        .padding(20)
        .frame(width: 320, height: 400, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func insightCard(_ insight: InsightPreviewItem) -> some View {
        ZStack(alignment: .topTrailing) {
            insightCardBody(insight)

            Button {
                Task {
                    await shareInsightCard(insight)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    //.padding(.top, 6)
                    //.padding(.trailing, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 320, height: 400, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func insightCardBody(_ insight: InsightPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\((insight.title ?? insight.viz ?? "Insight")) • \((activeGeo?.displayName ?? ""))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.trailing, 28)

            Text(capitalizedInsightHeadline(insight))
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let instanceID = insight.sourceID,
               let vizData = insightVizDataByID[instanceID] {

                if insight.type == "weekly_wow" {
                    WeeklyWowInsightChartView(
                        points: WeeklyWowInsightChartParser.parse(vizData.chartData),
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)

                } else if insight.type == "price_breakout_yoy" {
                    PriceBreakoutInsightChartView(
                        points: PriceBreakoutInsightChartParser.parse(vizData.chartData, bucket: vizData.bucket),
                        reportDate: insight.reportDate,
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)
                } else if insight.type == "monthly_yoy" {
                    MonthlyYoYInsightChartView(
                        points: MonthlyYoYInsightChartParser.parse(vizData.chartData),
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)
                } else {
                    chartPlaceholder(insight)
                        .frame(height: 220)
                }

            } else {
                chartPlaceholder(insight)
                    .frame(height: 220)
            }

            Text("Source: Indiana Association of REALTORS®")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chartPlaceholder(_ insight: InsightPreviewItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))

            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 34))
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

    private func capitalizedInsightHeadline(_ insight: InsightPreviewItem) -> String {
        let raw = insight.headline ?? insight.title ?? insight.viz ?? "Insight"
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    @MainActor
    private func shareInsightCard(_ insight: InsightPreviewItem) async {
        let content = insightCardBody(insight)
            .padding(20)
            .frame(width: 320, height: 400, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .preferredColorScheme(.light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale

        if let image = renderer.uiImage {
            shareItem = InsightShareItem(image: image)
        }
    }

    private func loadInsightVizData() async {
        var loaded: [Int: InsightVizData] = [:]

        for insight in insights.prefix(5) {
            guard (insight.type == "weekly_wow" || insight.type == "price_breakout_yoy" || insight.type == "monthly_yoy"),
                  let instanceID = insight.sourceID else { continue }

            if let vizData = await APIService.fetchInsightVizData(instanceID: instanceID, bucket: insight.bucket) {
                loaded[instanceID] = vizData
            }
        }

        insightVizDataByID = loaded
    }

    private func loadInsights() async {
        let trimmedID = String(geoID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            insights = []
            return
        }

        isLoadingInsights = true
        defer { isLoadingInsights = false }

        insights = await APIService.fetchInsightPreview(geoID: trimmedID, top: 5)
    }

    private var householdText: String {
        guard let households = activeGeo?.households else {
            return isLoadingGeo ? "Loading" : "—"
        }
        return households.formatted() + " households"
    }

    private func loadCurrentGeo() async {
        let trimmedID = String(geoID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            activeGeo = nil
            return
        }

        isLoadingGeo = true
        defer { isLoadingGeo = false }

        activeGeo = await APIService.fetchGeo(geoid: trimmedID)
    }
}

struct InsightsView: View {
    let geoID: Int
    @EnvironmentObject var app: AppState
    @State private var activeGeo: Geo?
    @State private var insights: [InsightPreviewItem] = []
    @State private var isLoadingInsights = false
    @State private var insightVizDataByID: [Int: InsightVizData] = [:]
    @State private var shareItem: InsightShareItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insights")
                        .font(.largeTitle.bold())

                    if let activeGeo {
                        Text(activeGeo.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)

                if isLoadingInsights && insights.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            insightSkeletonCard
                        }
                    }
                    .padding(.horizontal, 16)
                } else if insights.isEmpty {
                    Text("No insights available for this market yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(insights) { insight in
                            insightCard(insight)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCurrentGeo()
            await loadInsights()
            await loadInsightVizData()
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item.image])
        }
    }

    private var insightSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 150, height: 18)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray4))
                    .frame(height: 22)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray4))
                    .frame(width: 220, height: 22)
            }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 220)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 220, height: 14)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func insightCard(_ insight: InsightPreviewItem) -> some View {
        ZStack(alignment: .topTrailing) {
            insightCardBody(insight)

            Button {
                Task {
                    await shareInsightCard(insight)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 400, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func insightCardBody(_ insight: InsightPreviewItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\((insight.title ?? insight.viz ?? "Insight")) • \((activeGeo?.displayName ?? ""))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.trailing, 28)

            Text(capitalizedInsightHeadline(insight))
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let instanceID = insight.sourceID,
               let vizData = insightVizDataByID[instanceID] {

                if insight.type == "weekly_wow" {
                    WeeklyWowInsightChartView(
                        points: WeeklyWowInsightChartParser.parse(vizData.chartData),
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)

                } else if insight.type == "price_breakout_yoy" {
                    PriceBreakoutInsightChartView(
                        points: PriceBreakoutInsightChartParser.parse(vizData.chartData, bucket: vizData.bucket),
                        reportDate: insight.reportDate,
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)
                } else if insight.type == "monthly_yoy" {
                    MonthlyYoYInsightChartView(
                        points: MonthlyYoYInsightChartParser.parse(vizData.chartData),
                        format: vizData.format,
                        unit: vizData.unit
                    )
                    .frame(height: 220)
                } else {
                    chartPlaceholder(insight)
                        .frame(height: 220)
                }

            } else {
                chartPlaceholder(insight)
                    .frame(height: 220)
            }

            Text("Source: Indiana Association of REALTORS®")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chartPlaceholder(_ insight: InsightPreviewItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))

            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 34))
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

    private func capitalizedInsightHeadline(_ insight: InsightPreviewItem) -> String {
        let raw = insight.headline ?? insight.title ?? insight.viz ?? "Insight"
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    @MainActor
    private func shareInsightCard(_ insight: InsightPreviewItem) async {
        let content = insightCardBody(insight)
            .padding(20)
            .frame(width: 320, height: 400, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .preferredColorScheme(.light)
        
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale

        if let image = renderer.uiImage {
            shareItem = InsightShareItem(image: image)
        }
    }

    private func loadInsights() async {
        let trimmedID = String(geoID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            insights = []
            return
        }

        isLoadingInsights = true
        defer { isLoadingInsights = false }

        insights = await APIService.fetchInsightPreview(geoID: trimmedID, top: 20)
    }

    private func loadInsightVizData() async {
        var loaded: [Int: InsightVizData] = [:]

        for insight in insights {
            guard (insight.type == "weekly_wow" || insight.type == "price_breakout_yoy" || insight.type == "monthly_yoy"),
                  let instanceID = insight.sourceID else { continue }

            if let vizData = await APIService.fetchInsightVizData(instanceID: instanceID, bucket: insight.bucket) {
                loaded[instanceID] = vizData
            }
        }

        insightVizDataByID = loaded
    }

    private func loadCurrentGeo() async {
        let trimmedID = String(geoID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            activeGeo = nil
            return
        }

        activeGeo = await APIService.fetchGeo(geoid: trimmedID)
    }
}

private struct InsightShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
