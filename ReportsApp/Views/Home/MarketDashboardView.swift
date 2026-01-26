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
    struct Viz: Decodable { let viz_id: Int; let viz_title: String; let viz_subtitle: String?; let rows: [Row] }
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
    let latestReportDate: String?
    let series: [Double]
    let points: [SparkPoint]
}

// 2) Fetch (ETag optional but shown)
final class DashboardService {
    private var etagForURL: [String:String] = [:]

    func fetchTiles(geoID: String,
                    vizIDs: [Int],
                    proptype: String = "all",
                    facts: [String] = ["fact1","fact2"]) async throws -> [Tile] {

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

            return Tile(
                vizID: v.viz_id,
                title: v.viz_title,
                subtitleLabel: f2?.label,
                latestValue: f2?.value ?? f1?.value,
                latestDisplay: f2?.raw ?? f1?.raw,
                fact1Value: f1?.value,
                fact1Label: f1?.label,
                fact1Display: f1?.raw,
                latestReportDate: last?.report_date,
                series: seriesVals,
                points: points
            )
        }
    }
}

// 3) Views
struct Sparkline: View {
    let points: [SparkPoint]
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
        .frame(height: 44)
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
                    Text(p.value.formatted()).font(.caption2)
                }
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
                .padding(.bottom, 4)
            }
        }
    }
}

struct TileCard: View {
    let tile: Tile
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.title).font(.headline)
            if let d = tile.latestReportDate { Text(d).font(.caption).foregroundStyle(.secondary) }
            if let v = tile.latestValue {
                HStack(spacing: 8) {
                    Text(v.formatted()) // style as needed (currency, percent, etc.)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if let sVal = tile.fact1Value {
                        VStack(alignment: .leading, spacing: 0) {
                            Text((tile.fact1Display ?? sVal.formatted()))
                                .font(.subheadline).bold()
                            if let sLbl = tile.fact1Label { Text(sLbl).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if !tile.points.isEmpty { Sparkline(points: tile.points) }
        }
        .padding()
        .glassCard(cornerRadius: 12)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct MarketDashboardView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var app: AppState
    @State private var showGeoPicker = false
    @State private var showVizPicker = false
    @AppStorage("selectedGeoID") private var storedGeoID: String = "18"
    @AppStorage("dashboardVizIDs") private var vizIDsStored: String = "9,3,7"
    private var selectedVizIDs: [Int] {
        get { vizIDsStored.split(separator: ",").compactMap { Int($0) } }
        set { vizIDsStored = newValue.map(String.init).joined(separator: ",") }
    }
    @State private var tiles: [Tile] = []
    @State private var isLoading = true
    let geoID: String
    var vizIDs: [Int] { selectedVizIDs }

    var body: some View {
        let columns: [GridItem] = (hSize == .compact)
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        let skeletonCount = min(3, vizIDs.count)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                if isLoading {
                    ForEach(0..<skeletonCount) { _ in RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.15)).frame(height: 120) }
                } else {
                    ForEach(tiles) { TileCard(tile: $0) }
                }
            }
            .padding()
            VStack(spacing: 4) {
                Text("EDIT DASHBOARD")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Market") { showGeoPicker = true }
                        .font(.caption)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Metrics") { showVizPicker = true }
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
            do {
                let svc = DashboardService()
                let fetched = try await svc.fetchTiles(geoID: app.selectedGeoID, vizIDs: vizIDs)
                tiles = Array(fetched.prefix(3))
            } catch {
#if DEBUG
                print("Dashboard load error:", error)
#endif
                tiles = [];
            }
            isLoading = false
        }
        .onAppear {
            app.selectedGeoID = storedGeoID
        }
        .onChange(of: app.selectedGeoID) { newValue in
            storedGeoID = newValue
            isLoading = true
            Task {
                let svc = DashboardService()
                do {
                    let fetched = try await svc.fetchTiles(geoID: app.selectedGeoID, vizIDs: vizIDs)
                    tiles = Array(fetched.prefix(3))
                } catch { tiles = [] }
                isLoading = false
            }
        }
        .onChange(of: vizIDsStored) { _ in
            isLoading = true
            Task {
                let svc = DashboardService()
                do {
                    let fetched = try await svc.fetchTiles(geoID: app.selectedGeoID, vizIDs: vizIDs)
                    tiles = Array(fetched.prefix(3))
                } catch { tiles = [] }
                isLoading = false
            }
        }
        .sheet(isPresented: $showGeoPicker) {
            GeoPickerSheet(onSelectGeo: { newGeo in
                app.selectedGeoID = newGeo
                showGeoPicker = false
                isLoading = true
                Task {
                    let svc = DashboardService()
                    do {
                        let fetched = try await svc.fetchTiles(geoID: app.selectedGeoID, vizIDs: vizIDs)
                        tiles = Array(fetched.prefix(3))
                    } catch { tiles = [] }
                    isLoading = false
                }
            })
        }
        .sheet(isPresented: $showVizPicker) {
            VizPickerView(selected: Binding(
                get: { vizIDsStored.split(separator: ",").compactMap { Int($0) } },
                set: { newValue in
                    vizIDsStored = newValue.map(String.init).joined(separator: ",")
                }
            ))
        }
        .navigationTitle("Dashboard")
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


