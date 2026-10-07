//
//  CompareView.swift
//  ReportsApp
//
//  Two markets side by side: the same indicators, the same weeks, one
//  chart per indicator with both lines on it. Tap either name to change
//  that side; the metrics are the dashboard's.
//

import SwiftUI
import Charts

struct CompareView: View {
    @EnvironmentObject var app: AppState

    @State private var leftID: Int
    @State private var rightID: Int
    @State private var left: Geo?
    @State private var right: Geo?
    @State private var leftTiles: [Tile] = []
    @State private var rightTiles: [Tile] = []
    @State private var picking: CompareSide?
    @State private var showVizPicker = false
    /// The compare page's own metric set, apart from the dashboard's.
    @AppStorage("compareVizIDs") private var storedVizIDs: String = ""

    static let leftColor = BrandColors.teal
    static let rightColor = BrandColors.magenta

    init(leftID: Int, rightID: Int) {
        _leftID = State(initialValue: leftID)
        _rightID = State(initialValue: rightID)
    }

    /// The comparison report's monthly vizzes: counts per 1,000 households
    /// (closed sales, homes for sale, new listings, pendings), so a county
    /// and a ZIP compare on the same footing, then days on market, median
    /// price and the sale-to-list ratio.
    static let defaultVizIDs = [38, 36, 37, 39, 40, 41, 42]

    private var vizIDs: [Int] {
        let ids = storedVizIDs.split(separator: ",").compactMap { Int($0) }
        return ids.isEmpty ? Self.defaultVizIDs : ids
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(vizIDs, id: \.self) { vizID in
                    CompareRow(
                        leftName: left?.displayName ?? "…",
                        rightName: right?.displayName ?? "…",
                        left: leftTiles.first(where: { $0.vizID == vizID }),
                        right: rightTiles.first(where: { $0.vizID == vizID }),
                        loading: leftTiles.isEmpty || rightTiles.isEmpty)
                }
                askSpark
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .hubReadable()
        }
        .hubPage()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Metrics") { showVizPicker = true }
            }
        }
        .sheet(item: $picking) { side in
            GeoPickerSheet(current: side == .left ? leftID : rightID) { picked in
                guard let id = Int(picked) else { return }
                if side == .left { leftID = id } else { rightID = id }
            }
        }
        .sheet(isPresented: $showVizPicker) {
            VizPickerView(selected: Binding(
                get: { vizIDs },
                set: { storedVizIDs = $0.map(String.init).joined(separator: ",") }
            ))
        }
        // Either side or the metric set changing reloads both; a side that
        // didn't change comes straight back from the cache.
        .task(id: "\(leftID)-\(rightID)-\(vizIDs)") {
            async let a: Void = load(.left)
            async let b: Void = load(.right)
            _ = await (a, b)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            marketButton(.left, geo: left, color: Self.leftColor)
            Button {
                let l = leftID
                leftID = rightID
                rightID = l
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(HubStyle.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap sides")
            marketButton(.right, geo: right, color: Self.rightColor)
        }
    }

    private func marketButton(_ side: CompareSide, geo: Geo?, color: Color) -> some View {
        Button {
            picking = side
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(geo?.type.uppercased() ?? "MARKET")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                }
                HStack(spacing: 4) {
                    Text(geo?.displayName ?? "Choosing…")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var askSpark: some View {
        Button {
            let a = left?.displayName ?? "the first market"
            let b = right?.displayName ?? "the second market"
            app.sparkPrompt = "Compare \(a) and \(b): which is the stronger market right now, and why?"
            app.selectedTab = 2
        } label: {
            HStack(spacing: 12) {
                SparkMark(size: 18)
                    .frame(width: 32, height: 32)
                    .background(BrandColors.sparkTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Spark to compare them")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Which is stronger right now, and why")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .hubCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading

    private func load(_ side: CompareSide) async {
        let id = side == .left ? leftID : rightID
        let ids = vizIDs
        if side == .left { leftTiles = [] } else { rightTiles = [] }
        let fetchedGeo = await APIService.fetchGeo(geoid: String(id))
        guard (side == .left ? leftID : rightID) == id else { return }
        if side == .left { left = fetchedGeo } else { right = fetchedGeo }
        for await tiles in DashboardService.tiles(geoID: String(id), vizIDs: ids) {
            guard (side == .left ? leftID : rightID) == id, ids == vizIDs else { return }
            if side == .left { leftTiles = tiles } else { rightTiles = tiles }
        }
    }
}

enum CompareSide: String, Identifiable {
    case left, right
    var id: String { rawValue }
}

// MARK: - One indicator, two markets

struct CompareRow: View {
    let leftName: String
    let rightName: String
    let left: Tile?
    let right: Tile?
    let loading: Bool

    private struct Point: Identifiable {
        let id: String
        let series: String
        let x: Int
        let date: String
        let value: Double
    }

    private var title: String { left?.title ?? right?.title ?? " " }
    private var format: String? { left?.vizFormat ?? right?.vizFormat }

    private var points: [Point] {
        var out: [Point] = []
        for p in left?.points ?? [] {
            out.append(Point(id: "l\(p.x)", series: leftName, x: p.x, date: p.date, value: p.value))
        }
        for p in right?.points ?? [] {
            out.append(Point(id: "r\(p.x)", series: rightName, x: p.x, date: p.date, value: p.value))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let when = left?.latestReportDate ?? right?.latestReportDate {
                    Text(when)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                column(left, color: CompareView.leftColor)
                Divider().frame(height: 44)
                column(right, color: CompareView.rightColor)
            }

            if loading && points.isEmpty {
                RoundedRectangle(cornerRadius: 8).fill(HubStyle.chip).frame(height: 110)
            } else if !points.isEmpty {
                Chart(points) { p in
                    LineMark(x: .value("Period", p.x), y: .value("Value", p.value))
                        .foregroundStyle(by: .value("Market", p.series))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartForegroundStyleScale([leftName: CompareView.leftColor, rightName: CompareView.rightColor])
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(HubStyle.grid)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatTileValue(v, format: format))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 110)
                HStack {
                    Text(points.first?.date ?? "")
                    Spacer()
                    Text(points.last?.date ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .hubCard()
    }

    private func column(_ tile: Tile?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tile, let value = tile.latestValue {
                Text(formatTileValue(value, format: tile.vizFormat))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let f3 = tile.fact3Display, !f3.isEmpty {
                    Text([f3, tile.fact3Label ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if loading {
                RoundedRectangle(cornerRadius: 4).fill(HubStyle.chip).frame(width: 80, height: 24)
                RoundedRectangle(cornerRadius: 4).fill(HubStyle.chip).frame(width: 110, height: 12)
            } else {
                Text("No data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
