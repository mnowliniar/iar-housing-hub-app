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

// 2) Fetch (ETag optional but shown)
final class DashboardService {
    private var etagForURL: [String:String] = [:]

    func fetchTiles(geoID: String,
                    vizIDs: [Int],
                    proptype: String = "all",
                    facts: [String] = ["fact1","fact2","fact3"]) async throws -> [Tile] {

        let url = URL(string:
          "https://data.indianarealtors.com/api/viz_set/proptype/\(proptype)" +
          "?geo_ids=\(geoID)" +
          "&viz_ids=\(vizIDs.map(String.init).joined(separator: ","))" +
          "&facts=\(facts.joined(separator: ","))" +
          "&fmt=nested&compose=0&window=12&order=asc"
        )!
        print("url: \(url)")
        var req = URLRequest(url: url)
        if let tag = etagForURL[url.absoluteString] {
            req.addValue(tag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
#if DEBUG
        print("DashboardService status:", (resp as? HTTPURLResponse)?.statusCode ?? -1)
        if let s = String(data: data, encoding: .utf8) { print("DashboardService payload prefix:", s.prefix(200)) }
#endif
        if let http = resp as? HTTPURLResponse,
           let et = http.value(forHTTPHeaderField: "ETag") { etagForURL[url.absoluteString] = et }

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
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
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
                    .font(.system(size: 10).bold())
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
                        .font(.system(size: 32, weight: .bold, design: .rounded))

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
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
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
                .fill(.white.opacity(0.35))
                .frame(width: 120, height: 18)

            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.22))
                .frame(width: 80, height: 12)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.28))
                    .frame(width: 90, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.22))
                        .frame(width: 44, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.18))
                        .frame(width: 70, height: 10)
                }
            }

            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.16))
                .frame(height: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 12)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct MarketDashboardView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var app: AppState
    @State private var showGeoPicker = false
    @State private var showVizPicker = false
    @State private var activeGeo: Geo?
    @State private var isLoadingGeo = false
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
    @State private var showLoadedTiles = false
    @State private var showSkeletonTiles = true
    let geoID: String
    var vizIDs: [Int] { selectedVizIDs }

    var body: some View {
        ScrollView {
            Group {
                if hSize == .compact {
                    let skeletonCount = min(3, vizIDs.count)

                    ZStack(alignment: .topLeading) {
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            ForEach(0..<skeletonCount, id: \.self) { _ in
                                TileCardSkeleton()
                                    .frame(height: 169)
                            }
                        }
                        .opacity(showSkeletonTiles ? 1 : 0)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            ForEach(tiles) { tile in
                                TileCard(tile: tile)
                                    .frame(height: 169)
                                    .opacity(showLoadedTiles ? 1 : 0)
                            }
                        }
                    }
                    .padding()
                } else {
                    ZStack(alignment: .topLeading) {
                        if showSkeletonTiles {
                            dashboardWideSkeletonLayout
                                .opacity(showSkeletonTiles ? 1 : 0)
                        }

                        if showLoadedTiles {
                            dashboardWideLoadedLayout
                                .opacity(showLoadedTiles ? 1 : 0)
                        }
                    }
                    .padding()
                }
            }
            VStack(spacing: 4) {
                Text(activeGeo?.displayName ?? "Dashboard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Pick Market") { showGeoPicker = true }
                        .font(.caption)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Pick Metrics") { showVizPicker = true }
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(
                LinearGradient(
                    colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
        .task {
            await loadCurrentGeo()
            isLoading = true
            showSkeletonTiles = true
            showLoadedTiles = false
            do {
                let svc = DashboardService()
                let fetched = try await svc.fetchTiles(geoID: selectedGeoID, vizIDs: vizIDs)
                tiles = Array(fetched.prefix(3))
            } catch {
#if DEBUG
                print("Dashboard load error:", error)
#endif
                tiles = []
            }
            isLoading = false
            withAnimation(.easeInOut(duration: 0.25)) {
                showLoadedTiles = true
                showSkeletonTiles = false
            }
        }
        .onChange(of: app.selectedGeoID) { newValue in
            app.userPrefs.app.selectedGeoID = newValue
            showLoadedTiles = false
            app.saveUserPrefs()
            isLoading = true
            showSkeletonTiles = true
            showLoadedTiles = false
        }
        .onChange(of: app.userPrefs.app.dashboardVizIDs) { _ in
            app.saveUserPrefs()
            isLoading = true
            showSkeletonTiles = true
            showLoadedTiles = false
            Task {
                let svc = DashboardService()
                do {
                    let fetched = try await svc.fetchTiles(geoID: selectedGeoID, vizIDs: vizIDs)
                    tiles = Array(fetched.prefix(3))
                } catch { tiles = [] }
                isLoading = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLoadedTiles = true
                    showSkeletonTiles = false
                }
            }
        }
        .sheet(isPresented: $showGeoPicker) {
            GeoPickerSheet(onSelectGeo: { newGeo in
                app.selectedGeoID = newGeo
                app.userPrefs.app.dashboardGeoID = newGeo
                Task { await loadCurrentGeo() }
                showGeoPicker = false
                isLoading = true
                showSkeletonTiles = true
                showLoadedTiles = false
                Task {
                    let svc = DashboardService()
                    do {
                        let fetched = try await svc.fetchTiles(geoID: selectedGeoID, vizIDs: vizIDs)
                        tiles = Array(fetched.prefix(3))
                    } catch { tiles = [] }
                    isLoading = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLoadedTiles = true
                        showSkeletonTiles = false
                    }
                }
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
        .onChange(of: app.userPrefs.app.dashboardGeoID) { _ in
            Task {
                await loadCurrentGeo()
            }
        }
        .navigationTitle("Dashboard")
    }
    private func loadCurrentGeo() async {
        let trimmedID = selectedGeoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            activeGeo = nil
            return
        }

        isLoadingGeo = true
        defer { isLoadingGeo = false }
        print("[Dashboard] loadCurrentGeo selectedGeoID:", trimmedID)
        activeGeo = await APIService.fetchGeo(geoid: trimmedID)
        print("[Dashboard] activeGeo displayName:", activeGeo?.displayName)
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
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([VizItem].self, from: data)
            await MainActor.run {
                self.all = decoded
                self.isLoading = false
            }
        } catch {
            await MainActor.run { self.isLoading = false }
#if DEBUG
            print("viz fetch failed:", error)
#endif
        }
    }
}



