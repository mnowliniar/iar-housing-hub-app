//
//  DashboardResponse.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//


import SwiftUI
import Charts

// 1) Models (fmt=nested, compose=0)
struct DashboardResponse: Decodable {
    struct Meta: Decodable { let as_of: String? }
    struct Fact: Decodable {
        let value: Double?
        let label: String?
        let exp: String?
        let raw: String?      // original string if provided (e.g., "$248,000", "3.1%")

        enum CodingKeys: String, CodingKey { case value, label, exp }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try? c.decodeIfPresent(String.self, forKey: .label)
            exp   = try? c.decodeIfPresent(String.self, forKey: .exp)

            // If value was numeric in JSON
            if let n = try? c.decodeIfPresent(Double.self, forKey: .value) {
                value = n
                raw = String(n)
                return
            }
            // If value was a string in JSON, keep it as-is for display; also parse to Double for charts
            if let s = try? c.decodeIfPresent(String.self, forKey: .value) {
                raw = s
                let cleaned = s.replacingOccurrences(of: ",", with: "")
                               .replacingOccurrences(of: "%", with: "")
                               .replacingOccurrences(of: "$", with: "")
                               .trimmingCharacters(in: .whitespacesAndNewlines)
                value = Double(cleaned)
                return
            }
            value = nil
            raw = nil
        }
    }
    struct Row: Decodable { let report_date: String; let facts: [String: Fact]? }
    struct Viz: Decodable {
        let viz_id: Int
        let viz_title: String
        let viz_subtitle: String?
        let viz_timespan: String?
        let viz_format: String?
        let rows: [Row]
    }
    struct GeoBlock: Decodable { let geo_id: Int; let geo_name: String; let viz: [Viz] }
    let meta: Meta; let results: [GeoBlock]
}

struct SparkPoint: Identifiable {
    let id: Int
    let x: Int
    let date: String
    let value: Double
}

struct Tile: Identifiable {
    let id = UUID()
    let vizID: Int
    let title: String
    let subtitleLabel: String?   // fact2 label
    let latestValue: Double?     // numeric for chart & big number
    let latestDisplay: String?   // original formatted string for UI
    let fact1Value: Double?      // small stat numeric
    let fact1Label: String?      // label for the small stat
    let fact1Display: String?    // original formatted string for small stat
    let fact3Value: Double?
    let fact3Label: String?
    let fact3Display: String?
    let latestReportDate: String?
    let geoName: String?
    let vizFormat: String?
    let vizTimespan: String?
    let series: [Double]
    let points: [SparkPoint]
}

// 2) Fetch. Replies live in HubCache: the tiles a member saw last time
// come back at once, and the Hub is asked only when the week's data moved.
final class DashboardService {
    static func url(geoID: String, vizIDs: [Int], proptype: String = "all",
                    facts: [String] = ["fact1","fact2","fact3"]) -> URL {
        URL(string:
          "https://data.indianarealtors.com/api/viz_set/proptype/\(proptype)" +
          "?geo_ids=\(geoID)" +
          "&viz_ids=\(vizIDs.map(String.init).joined(separator: ","))" +
          "&facts=\(facts.joined(separator: ","))" +
          "&fmt=nested&compose=0&window=12&order=asc"
        )!
    }

    func fetchTiles(geoID: String, vizIDs: [Int]) async throws -> [Tile] {
        guard let data = await HubCache.data(Self.url(geoID: geoID, vizIDs: vizIDs), family: .data) else {
            throw URLError(.cannotLoadFromNetwork)
        }
        return try Self.tiles(from: data)
    }

    /// Cached tiles first, then this week's when the data moved.
    static func tiles(geoID: String, vizIDs: [Int]) -> AsyncStream<[Tile]> {
        HubCache.stream(url(geoID: geoID, vizIDs: vizIDs), family: .data) { try tiles(from: $0) }
    }

    static func tiles(from data: Data) throws -> [Tile] {
        let decoded = try JSONDecoder().decode(DashboardResponse.self, from: data)
        guard let geo = decoded.results.first else { return [] }

        return geo.viz.map { v in
            let points: [SparkPoint] = v.rows.enumerated().compactMap { (i, row) in
                if let val = row.facts?["fact2"]?.value ?? row.facts?["fact1"]?.value {
                    return SparkPoint(id: i, x: i, date: row.report_date, value: val)
                }
                return nil
            }
            let seriesVals = points.map { $0.value }
            let last = v.rows.last
            let f2 = last?.facts?["fact2"]
            let f1 = last?.facts?["fact1"]
            let f3 = last?.facts?["fact3"]

            return Tile(
                vizID: v.viz_id,
                title: v.viz_title,
                subtitleLabel: f2?.label,
                latestValue: f2?.value ?? f1?.value,
                latestDisplay: f2?.raw ?? f1?.raw,
                fact1Value: f1?.value,
                fact1Label: f1?.label,
                fact1Display: f1?.raw,
                fact3Value: f3?.value,
                fact3Label: f3?.label,
                fact3Display: f3?.raw,
                latestReportDate: last?.report_date,
                geoName: geo.geo_name,
                vizFormat: v.viz_format,
                vizTimespan: v.viz_timespan,
                series: seriesVals,
                points: points
            )
        }
    }
}

// 3) Views
struct Sparkline: View {
    let points: [SparkPoint]
    let vizFormat: String?
    let trendLabel: String?
    @State private var selectedX: Int? = nil
    @ScaledMetric(relativeTo: .caption2) private var trendLabelSize: CGFloat = 10

    var body: some View {
        let values = points.map { $0.value }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, max(abs(maxV), abs(minV)) * 0.05)
        let pad  = span * 0.10
        let lower = minV - pad
        let upper = maxV + pad

        return Chart(points, id: \.x) { p in
            LineMark(
                x: .value("t", p.x),
                y: .value("v", p.value)
            )
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .foregroundStyle(BrandColors.teal)

            if let sel = selectedX, sel == p.x {
                PointMark(
                    x: .value("t", p.x),
                    y: .value("v", p.value)
                )
                .symbolSize(45)
                .foregroundStyle(BrandColors.teal)
                RuleMark(x: .value("t", p.x))
                    .foregroundStyle(BrandColors.teal.opacity(0.6))
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .bottom)
        .padding(.top, 2)
        .chartOverlay { proxy in
            GeometryReader { geo in
                // Shared with the page's scroll instead of claiming the touch
                // (a claimed zero-distance drag meant a swipe that started on
                // a chart could never scroll Home). Sideways drags scrub; up
                // and down scrolls.
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                selectedX = nil
                                return
                            }
                            // Map x-location to nearest integer domain
                            let origin = geo[proxy.plotAreaFrame].origin
                            let plotX = value.location.x - origin.x
                            if let xVal: Int = proxy.value(atX: value.location.x) {
                                selectedX = xVal
                            } else {
                                // Fallback: clamp by width proportion
                                let count = max(points.count - 1, 1)
                                let w = proxy.plotAreaSize.width
                                let ratio = max(0, min(1, plotX / max(w, 1)))
                                selectedX = Int(round(ratio * Double(count)))
                            }
                        }
                        .onEnded { _ in selectedX = nil }
                    )
            }
        }
        .overlay(alignment: .topLeading) {
            if let sel = selectedX, let p = points.first(where: { $0.x == sel }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.date).font(.caption2).bold()
                    Text(formattedValue(p.value)).font(.caption2)
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let trendLabel, !trendLabel.isEmpty {
                Text(trendLabel)
                    .font(.system(size: trendLabelSize).bold())
                    .foregroundStyle(.secondary)
                    .shadow(color: Color(.systemBackground).opacity(0.98), radius: 3, x: 0, y: 0)
                    .shadow(color: Color(.systemBackground).opacity(0.98), radius: 3, x: 0, y: 0)
                    .shadow(color: Color(.systemBackground).opacity(0.98), radius: 1, x: 0, y: 0)
                    .padding(.leading, 2)
                    .padding(.bottom, 1)
            }
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch vizFormat {
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
}

struct TileCard: View {
    let tile: Tile
    var showFact3Row: Bool = false
    @ScaledMetric(relativeTo: .title) private var statFontSize: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.title).font(.headline)

            if let d = tile.latestReportDate {
                Text(tile.geoName.map { "\(d) • \($0)" } ?? d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let v = tile.latestValue {
                HStack(alignment: .top, spacing: 8) {
                    Text(formattedValue(v))
                        .font(.system(size: statFontSize, weight: .bold, design: .rounded))

                    if let sVal = tile.fact1Value {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tile.fact1Display ?? formattedValue(sVal))
                                .font(.subheadline).bold()

                            if let sLbl = tile.fact1Label {
                                Text(sLbl)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if showFact3Row,
                   let fact3Display = tile.fact3Display,
                   !fact3Display.isEmpty {
                    HStack(spacing: 4) {
                        Text(fact3Display)
                            .font(.caption)
                            .bold()

                        if let fact3Label = tile.fact3Label, !fact3Label.isEmpty {
                            Text(fact3Label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !tile.points.isEmpty {
                Sparkline(
                    points: tile.points,
                    vizFormat: tile.vizFormat,
                    trendLabel: tile.vizTimespan.map { "12-\($0.lowercased()) trend" }
                )
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .bottom)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .glassCard(cornerRadius: 12)
    }

    private func formattedValue(_ value: Double) -> String {
        switch tile.vizFormat {
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
}

struct TileCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 120, height: 18)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 12)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 90, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 44, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 70, height: 10)
                }
            }

            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(height: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 12)
    }
}

struct MarketDashboardView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var app: AppState
    @State private var showGeoPicker = false
    @State private var showVizPicker = false
    @State private var activeGeo: Geo?
    private var selectedVizIDs: [Int] {
        let ids = app.userPrefs.app.dashboardVizIDs
        return ids.isEmpty ? [9, 3, 7] : ids
    }
    private var selectedGeoID: String {
        let geoid = app.userPrefs.app.dashboardGeoID ?? ""
        return geoid.isEmpty ? "18" : geoid
    }
    @State private var tiles: [Tile] = []
    @State private var isLoading = true
    let geoID: String
    var vizIDs: [Int] { selectedVizIDs }

    var body: some View {
        VStack(spacing: 8) {
            if hSize == .compact {
                // A strip, not three stacked cards: the week's numbers in one
                // row, so what's under them is on screen without scrolling.
                HStack(alignment: .top, spacing: 10) {
                    if isLoading && tiles.isEmpty {
                        ForEach(0..<min(3, vizIDs.count), id: \.self) { _ in
                            MetricTileSkeleton()
                        }
                    } else {
                        ForEach(tiles) { tile in
                            MetricTile(tile: tile)
                        }
                    }
                }
                HStack {
                    Text(tiles.first?.latestReportDate ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit metrics") { showVizPicker = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                }
                .padding(.horizontal, 2)
            } else {
                ZStack(alignment: .topLeading) {
                    if isLoading && tiles.isEmpty {
                        dashboardWideSkeletonLayout
                    } else {
                        dashboardWideLoadedLayout
                    }
                }
                HStack(spacing: 12) {
                    Text(activeGeo?.displayName ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Pick market") { showGeoPicker = true }
                        .font(.caption.weight(.semibold))
                    Button("Edit metrics") { showVizPicker = true }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
        .task {
            await loadCurrentGeo()
            await reloadTiles()
        }
        .onChange(of: app.selectedGeoID) { _, newValue in
            // The tiles follow dashboardGeoID, not selectedGeoID. Opening a
            // favorite market changes selectedGeoID, and this handler used to
            // raise the skeleton with nothing left to lower it.
            app.userPrefs.app.selectedGeoID = newValue
            app.saveUserPrefs()
        }
        .onChange(of: app.userPrefs.app.dashboardVizIDs) { _, _ in
            app.saveUserPrefs()
            Task { await reloadTiles() }
        }
        .onChange(of: app.userPrefs.app.dashboardGeoID) { _, _ in
            // Fires for the picker and for saved prefs arriving after first
            // load; before, the latter updated the name but not the tiles.
            Task {
                await loadCurrentGeo()
                await reloadTiles()
            }
        }
        .sheet(isPresented: $showGeoPicker) {
            GeoPickerSheet(onSelectGeo: { newGeo in
                app.selectedGeoID = newGeo
                app.userPrefs.app.dashboardGeoID = newGeo
                app.saveUserPrefs()
                showGeoPicker = false
            })
        }
        .sheet(isPresented: $showVizPicker) {
            VizPickerView(selected: Binding(
                get: { selectedVizIDs },
                set: { newValue in
                    app.userPrefs.app.dashboardVizIDs = newValue
                }
            ))
        }
    }

    /// Fetches the three tiles for the current dashboard market and metrics.
    /// A reply that arrives after the market or metrics changed again is
    /// dropped, so a slow earlier request can't overwrite a newer one.
    private func reloadTiles() async {
        let geo = selectedGeoID
        let ids = vizIDs
        isLoading = true
        var shown = false
        for await fetched in DashboardService.tiles(geoID: geo, vizIDs: ids) {
            guard geo == selectedGeoID, ids == vizIDs else { return }
            shown = true
            withAnimation(.easeInOut(duration: 0.2)) {
                tiles = Array(fetched.prefix(3))
                isLoading = false
            }
        }
        guard geo == selectedGeoID, ids == vizIDs, !shown else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tiles = []
            isLoading = false
        }
    }

    private func loadCurrentGeo() async {
        let trimmedID = selectedGeoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            activeGeo = nil
            return
        }
        activeGeo = await APIService.fetchGeo(geoid: trimmedID)
    }

    private var dashboardWideSkeletonLayout: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let columnWidth = (geo.size.width - spacing) / 2
            let tileHeight: CGFloat = 169
            let featuredHeight = tileHeight * 2 + spacing

            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: spacing) {
                    TileCardSkeleton()
                        .frame(width: columnWidth, height: tileHeight)
                    TileCardSkeleton()
                        .frame(width: columnWidth, height: tileHeight)
                }

                TileCardSkeleton()
                    .frame(width: columnWidth, height: featuredHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 350)
    }

    @ViewBuilder
    private var dashboardWideLoadedLayout: some View {
        if tiles.count >= 3 {
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let columnWidth = (geo.size.width - spacing) / 2
                let tileHeight: CGFloat = 169
                let featuredHeight = tileHeight * 2 + spacing

                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        TileCard(tile: tiles[0])
                            .frame(width: columnWidth, height: tileHeight)
                        TileCard(tile: tiles[1])
                            .frame(width: columnWidth, height: tileHeight)
                    }

                    TileCard(tile: tiles[2], showFact3Row: true)
                        .frame(width: columnWidth, height: featuredHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 350)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(tiles) { tile in
                    TileCard(tile: tile)
                        .frame(height: 169)
                }
            }
        }
    }
}

/// A tile's value in its own format: dollars, percent, or a plain count.
func formatTileValue(_ value: Double, format: String?) -> String {
    switch format {
    case "$":
        return "$" + Int(value.rounded()).formatted()
    case "%":
        return value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
    default:
        return value.rounded() == value ? Int(value).formatted() : String(format: "%.1f", value)
    }
}

/// One metric in the strip: the name, the number, the change since the
/// period before, and a short line of the last twelve.
struct MetricTile: View {
    let tile: Tile

    private var deltaText: String? {
        let series = tile.series
        guard series.count >= 2 else { return nil }
        let last = series[series.count - 1]
        let previous = series[series.count - 2]
        guard previous != 0 else { return nil }
        let percent = Int(((last - previous) / abs(previous) * 100).rounded())
        let unit = (tile.vizTimespan ?? "").lowercased().hasPrefix("month") ? "mo" : "wk"
        if percent == 0 { return "flat \(unit)" }
        return (percent > 0 ? "+" : "−") + "\(abs(percent))% \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            if let value = tile.latestValue {
                Text(formatTileValue(value, format: tile.vizFormat))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(deltaText ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            MiniSparkline(values: tile.series)
                .frame(height: 22)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(padding: 12, cornerRadius: 14)
    }
}

struct MetricTileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(width: 60, height: 10)
            RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(width: 40, height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray4)).frame(width: 70, height: 20)
            RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(width: 40, height: 9)
            RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray6)).frame(height: 22).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(padding: 12, cornerRadius: 14)
    }
}

/// A line and nothing else. The tile is too small to scrub.
struct MiniSparkline: View {
    let values: [Double]

    var body: some View {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, max(abs(maxV), abs(minV)) * 0.05)
        let pad = span * 0.12
        return Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .foregroundStyle(BrandColors.teal)
        }
        .chartYScale(domain: (minV - pad)...(maxV + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct VizItem: Identifiable, Hashable, Decodable { let id: Int; let title: String; let subtitle: String?
     enum CodingKeys: String, CodingKey { case id = "viz_id", title = "viz_title", subtitle = "viz_subtitle" } }

struct VizPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @Binding var selected: [Int]

    @State private var all: [VizItem] = []
    @State private var isLoading = true
    private let popularIDs: Set<Int> = [9, 10, 3, 7, 29]

    var popular: [VizItem] { filtered.filter { popularIDs.contains($0.id) } }
    var others: [VizItem] { filtered.filter { !popularIDs.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !popular.isEmpty {
                            Section("Popular") {
                                ForEach(popular) { item in row(item) }
                            }
                        }
                        Section("All") {
                            ForEach(others) { item in row(item) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic))
            .navigationTitle("Choose up to 3")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            await loadVizzes()
        }
    }

    @ViewBuilder
    private func row(_ item: VizItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { selected.contains(item.id) },
                set: { on in
                    if on {
                        if selected.count < 3 || selected.contains(item.id) {
                            if !selected.contains(item.id) { selected.append(item.id) }
                        }
                    } else {
                        selected.removeAll { $0 == item.id }
                    }
                }
            ))
            .labelsHidden()
            .disabled(!selected.contains(item.id) && selected.count >= 3)
        }
    }

    private var filtered: [VizItem] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    private func loadVizzes() async {
        guard let url = URL(string: "https://data.indianarealtors.com/app/vizzes/") else { return }
        let decoded = await HubCache.value(url, family: .catalog, as: [VizItem].self) ?? []
        await MainActor.run {
            self.all = decoded
            self.isLoading = false
        }
    }
}



