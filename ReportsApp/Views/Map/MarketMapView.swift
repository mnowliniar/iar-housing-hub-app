//
//  MarketMapView.swift
//  ReportsApp
//
//  The Market Map: the web map's layers, native. Pick an indicator, a
//  place type and a period; tap a place for its numbers and a way into
//  its market page.
//

import SwiftUI
import MapKit

struct MarketMapView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var geo: MapGeo = .county
    @State private var indicator: MapIndicator = .sales
    @State private var period: MapPeriod = .oneMonth
    @State private var metric: MapMetric = .value
    @State private var layer: MapLayer?
    @State private var loading = false
    @State private var failed = false
    @State private var selected: MapFeature?
    @State private var openMarketID: Int?

    private var scale: MapScale {
        MapScale.scale(for: indicator, metric: effectiveMetric, geo: geo, period: period)
    }

    /// The heat index has no year-over-year layer.
    private var effectiveMetric: MapMetric { indicator.allowsYoY ? metric : .value }

    var body: some View {
        ZStack(alignment: .top) {
            MarketMapCanvas(layer: layer, fill: fill(for:), selectedID: selected?.id) { hit in
                withAnimation(.easeInOut(duration: 0.2)) { selected = hit }
            }
            .ignoresSafeArea(edges: .bottom)

            controls
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if loading {
                ProgressView("Loading the map…")
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 64)
            } else if failed {
                VStack(spacing: 8) {
                    Text("Couldn't load this layer.")
                        .font(.subheadline)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 64)
            }
        }
        .overlay(alignment: .bottomLeading) {
            legend
                .padding(12)
                .padding(.bottom, hSize == .compact && selected != nil ? 0 : 8)
        }
        .overlay(alignment: hSize == .regular ? .bottomTrailing : .bottom) {
            if let selected {
                detail(selected)
                    .frame(maxWidth: hSize == .regular ? 340 : .infinity)
                    .padding(12)
                    .transition(.move(edge: hSize == .regular ? .trailing : .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Market Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openMarketID) { geoID in
            MarketView(geoID: geoID)
                .environmentObject(app)
        }
        .task(id: "\(geo.rawValue)-\(indicator.rawValue)-\(period.rawValue)") {
            await load()
        }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        failed = false
        selected = nil
        do {
            let fetched = try await MapLayerService.load(geo: geo, indicator: indicator, period: period)
            guard fetched.geo == geo, fetched.indicator == indicator, fetched.period == period else { return }
            layer = fetched
        } catch {
            if !Task.isCancelled { failed = true }
        }
        loading = false
    }

    // MARK: Colors

    /// The web map's rules: the ramp's color, or nothing for a place with
    /// no number, a tiny count's change, or the two townships-only counties.
    private func fill(for feature: MapFeature) -> UIColor? {
        if geo == .township {
            let prefix = String(feature.id.prefix(5))
            if prefix == "18177" || prefix == "18135" { return nil }
        }
        switch (indicator, effectiveMetric) {
        case (.marketheat, _):
            guard let v = feature.value else { return nil }
            return scale.color(v * 100)
        case (_, .yoy):
            guard let yoy = feature.yoy else { return nil }
            if indicator.isCount, (feature.prev ?? 0) < 5, (feature.value ?? 0) < 5 { return nil }
            return scale.color(yoy)
        case (.dom, .value), (.price, .value), (.pctlist, .value):
            guard feature.mapstat != nil, let v = feature.value else { return nil }
            return scale.color(v)
        default:
            return scale.color(feature.value ?? 0)
        }
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { controlMenus }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { indicatorMenu; geoMenu }
                HStack(spacing: 8) { periodMenu; yoyToggle }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controlMenus: some View {
        indicatorMenu
        geoMenu
        periodMenu
        yoyToggle
    }

    private var indicatorMenu: some View {
        Menu {
            Picker("Indicator", selection: $indicator) {
                ForEach(MapIndicator.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            pill(indicator.label, icon: "chart.bar")
        }
    }

    private var geoMenu: some View {
        Menu {
            Picker("Places", selection: $geo) {
                ForEach(MapGeo.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            pill(geo.label, icon: "square.grid.3x3")
        }
    }

    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                ForEach(MapPeriod.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            pill(period.label, icon: "calendar")
        }
    }

    @ViewBuilder
    private var yoyToggle: some View {
        if indicator.allowsYoY {
            Button {
                metric = metric == .yoy ? .value : .yoy
            } label: {
                pill("Year over year", icon: metric == .yoy ? "checkmark.circle.fill" : "circle",
                     on: metric == .yoy)
            }
        }
    }

    private func pill(_ text: String, icon: String, on: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(on ? AnyShapeStyle(BrandColors.teal) : AnyShapeStyle(.regularMaterial), in: Capsule())
        .overlay(Capsule().stroke(HubStyle.hairline, lineWidth: 1))
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(effectiveMetric == .yoy ? "\(indicator.label) · year-over-year change" : indicator.label)
                .font(.caption.weight(.semibold))
            LinearGradient(colors: scale.samples().map { Color($0) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 180, height: 10)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(HubStyle.hairline, lineWidth: 1))
            HStack {
                Text(MapWords.legendEnd(scale.low, indicator: indicator, metric: effectiveMetric))
                Spacer()
                Text(MapWords.legendEnd((scale.low + scale.high) / 2, indicator: indicator, metric: effectiveMetric))
                Spacer()
                Text(MapWords.legendEnd(scale.high, indicator: indicator, metric: effectiveMetric))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 180)
            if let date = MapWords.date(layer?.measureDate, period: period) {
                Text("\(period.label) · \(date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: The tapped place

    private func detail(_ feature: MapFeature) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(geo.singular.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Text(feature.name)
                        .font(.title3.weight(.bold))
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let v = feature.value {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MapWords.value(v, indicator: indicator))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(unitLine(for: v))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if indicator == .marketheat {
                    heatParts(feature)
                } else if let yoy = feature.yoy {
                    HStack(spacing: 4) {
                        Image(systemName: yoy >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                        Text("\(MapWords.yoy(yoy)) vs. a year ago")
                            .font(.subheadline.weight(.medium))
                        if let prev = feature.prev {
                            Text("· was \(MapWords.value(prev, indicator: indicator))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(yoy >= 0 ? BrandColors.teal : BrandColors.magenta)
                }
            } else {
                Text("No number for this place in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    openMarketID = feature.geoid
                } label: {
                    Label("Open market", systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColors.teal)
                Button {
                    app.sparkPrompt = "What's happening in \(feature.name)\(geo == .county ? " County" : "")?"
                    app.selectedTab = 2
                } label: {
                    Label("Ask Spark", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HubStyle.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func unitLine(for value: Double) -> String {
        switch indicator {
        case .sales: return "closed sales"
        case .listings: return "new listings"
        case .pends: return "new pending contracts"
        case .price: return "median sale price"
        case .pctlist: return "of list price"
        case .dom: return "median"
        case .marketheat: return MapWords.heatBand(value * 100)
        }
    }

    /// What the heat index is made of, when the file carries the parts.
    @ViewBuilder
    private func heatParts(_ feature: MapFeature) -> some View {
        let dom = feature.extras["dom_value"]
        let pct = feature.extras["pctlist_value"]
        let absorption = feature.extras["absorption_value"]
        if dom != nil || pct != nil || absorption != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let dom { Text("Days on market: \(Int(dom.rounded()))") }
                if let pct { Text(String(format: "Pct. of list price: %.1f%%", pct * 100)) }
                if let absorption { Text(String(format: "Absorption: %.0f%%", absorption * 100)) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
