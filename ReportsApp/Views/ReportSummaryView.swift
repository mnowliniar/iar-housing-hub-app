//
//  ReportSummaryView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 8/26/25.
//


import SwiftUI
import Charts
import WebKit
import UIKit

struct ReportSummaryView: View {
    let report: Report
    let geo: Geo
    let updateDate: String

    @State private var summary: ReportSummary?
    @State private var isLoading = true
    @State private var exportItem: ExportURLItem?
    @State private var shareItem: ShareURLItem?
    @State private var cardShare: InsightShareItem?
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ScrollView {
            if let summary = summary {
                VStack(alignment: .leading, spacing: hSize == .regular ? 20 : 12) {
                    // Title area
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.title)
                                    .font(.title2).bold()
                                Text(summary.geo)
                                    .font(.subheadline).foregroundColor(.secondary)
                                Text(summary.report_date)
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 12) {
                                Button {
                                    Task {
                                        if let url = await fetchShareURL() {
                                            shareItem = ShareURLItem(url: url)
                                        }
                                    }
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                }

                                Button {
                                    guard let url = makeWebReportURL() else { return }
                                    debugLog("Export URL:", url.absoluteString)
                                    exportItem = ExportURLItem(url: url)
                                    EventTracker.fire(.exportChart, metadata: [
                                        "kind": "report_print",
                                        "report_id": String(report.id),
                                        "geo_id": String(geo.geoid),
                                    ])
                                } label: {
                                    Label("Print", systemImage: "printer")
                                        .labelStyle(.iconOnly)
                                        .font(.title3)
                                }
                            }
                            .accessibilityLabel("Report actions")
                        }
                    }
                    .padding(.horizontal, hSize == .regular ? 32 : 16)

                    Divider()

                    // Cards
                    ForEach(summary.vizzes) { viz in
                        ReportVizCard(viz: viz) {
                            shareCard(viz)
                        }
                        .padding(.horizontal, hSize == .regular ? 32 : 16)
                    }
                }
            } else if isLoading {
                ProgressView("Loading...")
                    .padding()
            } else {
                Text("Failed to load report.")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        //.navigationTitle("Summary")
        // Fill the screen whatever the content's height: attached to the
        // scroll view alone, the gradient only covered "Loading..." until
        // the report arrived.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hubPage()
        .task {
            debugLog("Loading summary for \(geo.geoid), \(updateDate)")
            await loadSummary()
            // Fired here rather than in ReportDetailView: the Home rail's
            // "all reports" list opens this view directly, and those views
            // went uncounted. After the load, so the title and area name are
            // the report's own: the web's habit rows ("Your reports") are
            // built from these fields, as the web's own report views send them.
            EventTracker.fire(.viewReports, metadata: [
                "report_id": String(report.id),
                "report_title": summary?.title ?? report.title,
                "geo_id": String(geo.geoid),
                "geo_label": summary?.geo ?? geo.displayName,
                "proptype": "all",
                "surface": "ios_app",
            ])
        }
        .sheet(item: $exportItem) { item in
            WebReportPrintView(url: item.url)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .sheet(item: $cardShare, onDismiss: {
            cardShare?.cleanup()
            cardShare = nil
        }) { item in
            ActivityViewController(activityItems: [item.activityItemSource])
        }
    }

    /// One chart of the report as an image: the card as drawn, plus the
    /// report's name and the source, at a width that reads on a phone.
    @MainActor
    private func shareCard(_ viz: VizSummary) {
        let package = viz.chart_data.flatMap {
            VizNormalizer.makePackage(chartData: $0, type: viz.type ?? "", format: viz.format ?? "default", variant: nil, title: viz.title)
        }
        let caption = "\(summary?.title ?? report.title) · \(summary?.geo ?? geo.displayName) · \(summary?.report_date ?? updateDate)"
        let content = VStack(alignment: .leading, spacing: 10) {
            ReportVizCard(viz: viz, package: package, fitsWidth: true)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            Text("Source: Indiana Association of REALTORS®")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 390)
        .background(Color.white)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .large)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage,
           let item = InsightShareItem.make(image: image, title: "\(viz.title) · \(summary?.geo ?? geo.displayName)") {
            cardShare = item
            EventTracker.fire(.exportChart, metadata: [
                "kind": "report_card",
                "report_id": String(report.id),
                "viz_id": String(viz.vizid),
                "geo_id": String(geo.geoid),
            ])
        }
    }

    func loadSummary() async {
        isLoading = true
        debugLog("Calling APIService.fetchReportSummary")
        summary = await APIService.fetchReportSummary(
            reportID: report.id,
            updateDate: updateDate,
            geoID: geo.geoid
        )
        isLoading = false
    }

    func makeWebReportURL() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: updateDate) else { return nil }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        let baseURLString = "https://data.indianarealtors.com"
        let path = "/reports/viewreport/onepager/\(report.id)/\(geo.geoid)/\(year)/\(month)/\(day)/"
        return URL(string: baseURLString + path)
    }

    func fetchShareURL() async -> URL? {
        // chat_user_id lets the server credit the member with copy_share_link.
        guard let url = URL(string: "https://data.indianarealtors.com/api/create-report-share/")?.appendingChatUserID() else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: updateDate) else { return nil }

        let calendar = Calendar.current

        let payload: [String: Any] = [
            "report_id": report.id,
            "geo_id": geo.geoid,
            "year": calendar.component(.year, from: date),
            "month": calendar.component(.month, from: date),
            "day": calendar.component(.day, from: date),
            "proptype": "all"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, _) = try await URLSession.shared.data(for: request.withAppIdentity())

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let urlString = json["url"] as? String {
                return URL(string: urlString)
            }
        } catch {
            debugLog("Share link error:", error)
        }

        return nil
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let expected: String?
    var tint: Color = BrandColors.teal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let expected, !expected.isEmpty {
                Text(expected)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HubStyle.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// One chart of a report, drawn like an insight card: the main fact as the
/// hero number, the chart, the other facts in quiet chips, a share button.
struct ReportVizCard: View {
    let viz: VizSummary
    /// A chart package built ahead of time, for the share image.
    var package: DataPackage? = nil
    /// Draw the whole series in the width given, instead of a scrolling plot.
    var fitsWidth: Bool = false
    var onShare: (() -> Void)? = nil

    private struct Chip: Identifiable {
        let id: Int
        let label: String
        let value: String
        let expected: String?
    }

    private var chips: [Chip] {
        var out: [Chip] = []
        if let label = viz.fact1label, let value = viz.fact1 {
            out.append(Chip(id: 1, label: label, value: value, expected: viz.exp1))
        }
        if let label = viz.fact3label, let value = viz.fact3 {
            out.append(Chip(id: 3, label: label, value: value, expected: viz.exp3))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viz.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrandColors.teal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share this chart")
                }
            }

            if let value = viz.fact2 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(value)
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let expected = viz.exp2, !expected.isEmpty {
                        Text(expected)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let label = viz.fact2label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let chartData = viz.chart_data, let type = viz.type {
                DataChartView(
                    chartData: chartData,
                    type: type,
                    color: .blue,
                    title: viz.title,
                    format: viz.format ?? "default",
                    package: package,
                    fitsWidth: fitsWidth
                )
                .padding(.top, 4)
            }

            if !chips.isEmpty {
                HStack(spacing: 10) {
                    ForEach(chips) { chip in
                        StatChip(label: chip.label, value: chip.value, expected: chip.expected)
                    }
                }
                .padding(.top, 2)
            }
        }
        .hubCard()
    }
}

struct HeroFactRow: View {
    let label: String
    let value: String
    let expected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
            }
            if let expected = expected, !expected.isEmpty {
                HStack {
                    Spacer()
                    Text(expected)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 240, alignment: .trailing)
                }
            }
        }
    }
}

struct FactRow: View {
    let label: String
    let value: String
    let expected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // First row: label and value side by side
            HStack {
                Text(label + ":")
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.body).bold()
            }

            // Second row: expected value (if present), left-aligned
            if let expected = expected {
                Text(expected)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DataChartView: View {
    let chartData: [[String: JSONValue]]
    // Grow the plot with Dynamic Type so larger axis/legend labels don't crush it.
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 200
    let type: String
    let color: Color
    let title: String
    let format: String

    // Series and DataPackage structs removed

    @State private var dataPackage: DataPackage
    @State private var isLoading: Bool
    /// Draw the whole series in the width given (a share image has no scroll).
    let fitsWidth: Bool

    init(chartData: [[String: JSONValue]], type: String, color: Color, title: String, format: String,
         package: DataPackage? = nil, fitsWidth: Bool = false) {
        self.chartData = chartData
        self.type = type
        self.color = color
        self.title = title
        self.format = format
        self.fitsWidth = fitsWidth
        _dataPackage = State(initialValue: package ?? DataPackage())
        _isLoading = State(initialValue: package == nil)
    }
    
    // Helpers
    
    // Formats the y axis labels
    func formatValue(_ v: Double) -> String {
        let nf = NumberFormatter()
        switch format {
        case "$":
            nf.numberStyle = .currency
            nf.currencyCode = "USD"
            nf.maximumFractionDigits = 0
            nf.minimumFractionDigits = 0
        case "%":
            nf.numberStyle = .percent
            nf.maximumFractionDigits = 0
            nf.minimumFractionDigits = 0
        default:
            nf.numberStyle = .decimal
            nf.maximumFractionDigits = 0
        }
        return nf.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    
    // Defines the filtered color scale
    func activeColorScale() -> (domain: [String], range: [Color]) {
        let allColors: [String: Color] = [
            "Selected Area": BrandColors.teal,
            "Indiana": BrandColors.teal.opacity(0.4),
            "Comparison": BrandColors.teal.opacity(0.4),
            "Current": BrandColors.teal,
            "Weekly": .gray.opacity(0.5),
            "Previous Year": BrandColors.teal.opacity(0.4),
            "Last 3 weeks": BrandColors.teal,
            "Prior 6 weeks": .gray.opacity(0.5),
            "YoY Recent": .gray.opacity(0.2),
            "YoY Previous": .gray.opacity(0.2)
        ]
        var seen = Set<String>()
        let domain = dataPackage.series.compactMap { s in
            seen.insert(s.name).inserted ? s.name : nil
        }
        let range = domain.map { allColors[$0] ?? BrandColors.teal }
        return (domain, range)
    }
    
    // Applies the filtered color scale
    struct ColorScale: ViewModifier {
        let domain: [String]
        let range: [Color]
        func body(content: Content) -> some View {
            content.chartForegroundStyleScale(domain: domain, range: range)
        }
    }

    // Formats the Y axis using your simple formatter
    struct YAxisFormat: ViewModifier {
        let formatValue: (Double) -> String
        func body(content: Content) -> some View {
            content.chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(HubStyle.grid)
                    if let d = value.as(Double.self) {
                        AxisValueLabel { Text(formatValue(d)) }
                    }
                }
            }
        }
    }

    // Chooses reasonable XTicks (dates if available, else every Nth label)
    struct XAxisConfig: ViewModifier {
        let dates: [Date]?
        let labels: [String]
        func body(content: Content) -> some View {
            content.chartXAxis {
                if let ds = dates, !ds.isEmpty {
                    AxisMarks(values: .automatic)
                } else {
                    let step = max(1, labels.count / 8)
                    let ticks = labels.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
                    AxisMarks(values: ticks) { AxisGridLine().foregroundStyle(HubStyle.grid); AxisValueLabel().offset(y: 7) }
                }
            }
            .chartPlotStyle { plot in
                plot
                    .padding(.bottom, 8)   // minimal space for x labels
                    .padding(.top, 0)      // remove extra headroom
                    .padding(.trailing, 0) // align with card padding
            }
        }
    }
    // --- Insert SeriesChart subview just above body:
    struct SeriesChart: View {
        let labels: [String]
        let dates: [Date]?
        let series: [Series]
        let type: String
        let colors: [String: Color]

        var body: some View {
            Chart {
                switch type {
                case "yoyExp":
                    let currentSeries = series.first(where: { $0.name == "Current" })
                    let previousSeries = series.first(where: { $0.name == "Previous Year" })
                    let lowSeries = series.first(where: { $0.name == "Expected Low" })
                    let highSeries = series.first(where: { $0.name == "Expected High" })

                    if let lowSeries, let highSeries {
                        let endBand: Int = {
                            if let ds = dates, !ds.isEmpty {
                                return Swift.min(labels.count, lowSeries.values.count, highSeries.values.count, ds.count)
                            } else {
                                return Swift.min(labels.count, lowSeries.values.count, highSeries.values.count)
                            }
                        }()

                        ForEach(0..<endBand, id: \.self) { i in
                            let low = lowSeries.values[i]
                            let high = highSeries.values[i]
                            if low.isFinite && high.isFinite {
                                if let ds = dates, i < ds.count {
                                    AreaMark(
                                        x: .value("Date", ds[i]),
                                        yStart: .value("Expected Low", low),
                                        yEnd: .value("Expected High", high)
                                    )
                                    .foregroundStyle(BrandColors.teal.opacity(0.2))
                                } else {
                                    AreaMark(
                                        x: .value("Label", labels[i]),
                                        yStart: .value("Expected Low", low),
                                        yEnd: .value("Expected High", high)
                                    )
                                    .foregroundStyle(BrandColors.teal.opacity(0.2))
                                }
                            }
                        }
                    }

                    ForEach([currentSeries, previousSeries].compactMap { $0 }, id: \.name) { lineSeries in
                        let endLine: Int = {
                            if let ds = dates, !ds.isEmpty {
                                return Swift.min(labels.count, lineSeries.values.count, ds.count)
                            } else {
                                return Swift.min(labels.count, lineSeries.values.count)
                            }
                        }()

                        ForEach(0..<endLine, id: \.self) { i in
                            let y = lineSeries.values[i]
                            if y.isFinite {
                                if let ds = dates, i < ds.count {
                                    LineMark(
                                        x: .value("Date", ds[i]),
                                        y: .value(lineSeries.name, y)
                                    )
                                    .lineStyle(StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round,
                                        miterLimit: 2
                                    ))
                                    .foregroundStyle(by: .value("Series", lineSeries.name))
                                } else {
                                    LineMark(
                                        x: .value("Label", labels[i]),
                                        y: .value(lineSeries.name, y)
                                    )
                                    .lineStyle(StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round,
                                        miterLimit: 2
                                    ))
                                    .foregroundStyle(by: .value("Series", lineSeries.name))
                                }
                            }
                        }

                        if let last = (0..<endLine).last(where: { i in
                            i < lineSeries.values.count && lineSeries.values[i].isFinite
                        }) {
                            if let ds = dates, last < ds.count {
                                PointMark(
                                    x: .value("Date", ds[last]),
                                    y: .value(lineSeries.name, lineSeries.values[last])
                                )
                                .symbol(.circle)
                                .symbolSize(30)
                                .foregroundStyle(by: .value("Series", lineSeries.name))
                            } else {
                                PointMark(
                                    x: .value("Label", labels[last]),
                                    y: .value(lineSeries.name, lineSeries.values[last])
                                )
                                .symbol(.circle)
                                .symbolSize(30)
                                .foregroundStyle(by: .value("Series", lineSeries.name))
                            }
                        }
                    }

                default:
                    ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                        let end: Int = {
                            if let ds = dates, !ds.isEmpty {
                                return Swift.min(labels.count, s.values.count, ds.count)
                            } else {
                                return Swift.min(labels.count, s.values.count)
                            }
                        }()

                        switch type {
                        case "barCat":
                            let endBar = Swift.min(labels.count, s.values.count)
                            let barData: [(idx: Int, label: String, value: Double)] = (0..<endBar).compactMap { i in
                                let y = s.values[i]
                                guard i < labels.count, y.isFinite else { return nil }
                                return (i, labels[i], y)
                            }
                            ForEach(barData, id: \.idx) { point in
                                BarMark(
                                    x: .value("Category", point.label),
                                    y: .value(s.name, point.value)
                                )
                                .foregroundStyle(by: .value("Series", s.name))
                            }

                        case "barGrouped":
                            let endBar = Swift.min(labels.count, s.values.count)
                            let barData: [(idx: Int, label: String, value: Double)] = (0..<endBar).compactMap { i in
                                let y = s.values[i]
                                guard i < labels.count, y.isFinite else { return nil }
                                return (i, labels[i], y)
                            }
                            ForEach(barData, id: \.idx) { point in
                                BarMark(
                                    x: .value("Category", point.label),
                                    y: .value(s.name, point.value)
                                )
                                .position(by: .value("Series", s.name))
                                .foregroundStyle(by: .value("Series", s.name))
                            }

                        case "dotPlot":
                            ForEach(0..<end, id: \.self) { i in
                                if let ds = dates, i < ds.count {
                                    PointMark(
                                        x: .value("Date", ds[i]),
                                        y: .value(s.name, s.values[i])
                                    )
                                    .symbol(.circle)
                                    .foregroundStyle(by: .value("Series", s.name))
                                } else {
                                    PointMark(
                                        x: .value("Label", labels[i]),
                                        y: .value(s.name, s.values[i])
                                    )
                                    .symbol(.circle)
                                    .foregroundStyle(by: .value("Series", s.name))
                                }
                            }

                        default:
                            ForEach(0..<end, id: \.self) { i in
                                if let ds = dates, i < ds.count {
                                    LineMark(
                                        x: .value("Date", ds[i]),
                                        y: .value(s.name, s.values[i])
                                    )
                                    .lineStyle(StrokeStyle(
                                        lineWidth: (type == "lineTrend" && s.name == "Weekly") ? 1 : 4,
                                        lineCap: .round,
                                        lineJoin: .round,
                                        miterLimit: 2
                                    ))
                                    .foregroundStyle(by: .value("Series", s.name))
                                } else {
                                    LineMark(
                                        x: .value("Label", labels[i]),
                                        y: .value(s.name, s.values[i])
                                    )
                                    .lineStyle(StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round,
                                        miterLimit: 2
                                    ))
                                    .foregroundStyle(by: .value("Series", s.name))
                                }
                            }

                            if let last = (0..<end).last(where: { i in
                                i < s.values.count && s.values[i].isFinite
                            }) {
                                if let ds = dates, last < ds.count {
                                    PointMark(
                                        x: .value("Date", ds[last]),
                                        y: .value(s.name, s.values[last])
                                    )
                                    .symbol(.circle)
                                    .symbolSize(30)
                                    .foregroundStyle(by: .value("Series", s.name))
                                } else {
                                    PointMark(
                                        x: .value("Label", labels[last]),
                                        y: .value(s.name, s.values[last])
                                    )
                                    .symbol(.circle)
                                    .symbolSize(30)
                                    .foregroundStyle(by: .value("Series", s.name))
                                }
                            }

                            if type == "lineTrend" && s.name == "Last 3 weeks" {
                                if let last = (0..<end).last(where: { i in
                                    i < s.values.count && s.values[i].isFinite
                                }) {
                                    if let ds = dates, last < ds.count {
                                        PointMark(x: .value("Date", ds[last]), y: .value(s.name, s.values[last]))
                                            .symbol(.circle)
                                            .foregroundStyle(by: .value("Series", s.name))
                                            .opacity(0)
                                            .annotation(position: .trailing, alignment: .trailing) {
                                                Text(s.name)
                                                    .font(.caption2)
                                                    .foregroundColor(colors[s.name] ?? .secondary)
                                            }
                                    } else {
                                        PointMark(x: .value("Label", labels[last]), y: .value(s.name, s.values[last]))
                                            .symbol(.circle)
                                            .foregroundStyle(by: .value("Series", s.name))
                                            .opacity(0)
                                            .annotation(position: .trailing, alignment: .trailing) {
                                                Text(s.name)
                                                    .font(.caption2)
                                                    .foregroundColor(colors[s.name] ?? .secondary)
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Add yDomain helper:
    var yDomain: ClosedRange<Double> {
        let vals = dataPackage.series.flatMap { $0.values }.filter { !$0.isNaN && $0.isFinite }
        guard let loRaw = vals.min(), let hiRaw = vals.max(), loRaw.isFinite, hiRaw.isFinite else {
            return 0...1
        }
        // Bar chart types should start at zero for honest bar lengths
        let isBar = (type == "barGrouped" || type == "barWeek" || type == "barCat")
        let lo = isBar ? min(0.0, loRaw) : loRaw
        let hi = max(hiRaw, lo) // ensure non-negative span
        let span = max(hi - lo, 1e-9)
        let padLo = isBar ? 0.0 : span * 0.02
        let padHi = span * 0.12  // extra headroom for top labels
        return (lo - padLo)...(hi + padHi)
    }

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView()
            } else {
                let scale = activeColorScale()
                let colorMap = Dictionary(uniqueKeysWithValues: zip(scale.domain, scale.range))
                let pointCount = dataPackage.dates?.count ?? dataPackage.labels.count
                let contentWidth = max(CGFloat(pointCount) * 12.0, 360)

                if type == "lineTrend" && !fitsWidth {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                let colorMap = Dictionary(uniqueKeysWithValues: zip(scale.domain, scale.range))
                                SeriesChart(labels: dataPackage.labels,
                                            dates: dataPackage.dates,
                                            series: dataPackage.series,
                                            type: type,
                                            colors: colorMap)
                                .modifier(ColorScale(domain: scale.domain, range: scale.range))
                                .modifier(YAxisFormat(formatValue: formatValue))
                                .modifier(XAxisConfig(dates: dataPackage.dates, labels: dataPackage.labels))
                                .chartLegend(.hidden)
                                .chartYScale(domain: yDomain)
                                .frame(width: contentWidth, height: chartHeight)

                                // Invisible anchor at the far right
                                Color.clear.frame(width: 1, height: 1).id("end")
                            }
                        }
                        .onAppear {
                            proxy.scrollTo("end", anchor: .trailing)
                        }
                        .onChange(of: pointCount) { _ in
                            proxy.scrollTo("end", anchor: .trailing)
                        }
                    }
                } else {
                    let colorMap = Dictionary(uniqueKeysWithValues: zip(scale.domain, scale.range))
                    SeriesChart(labels: dataPackage.labels,
                                dates: dataPackage.dates,
                                series: dataPackage.series,
                                type: type,
                                colors: colorMap)
                    .modifier(ColorScale(domain: scale.domain, range: scale.range))
                    .modifier(YAxisFormat(formatValue: formatValue))
                    .modifier(XAxisConfig(dates: dataPackage.dates, labels: dataPackage.labels))
                    .chartLegend(dataPackage.series.count > 1 ? .visible : .hidden)
                    .chartYScale(domain: yDomain)
                    .frame(height: chartHeight)
                }
            }
        }
        .task {
            if let pkg = VizNormalizer.makePackage(
                chartData: chartData,
                type: type,
                format: format,
                variant: nil,
                title: title
            ) {
                self.dataPackage = pkg
            }
            self.isLoading = false
        }
    }

}

struct WebReportPrintView: View {
    let url: URL

    var body: some View {
        WebReportPrintController(url: url)
            .ignoresSafeArea()
    }
}

struct WebReportPrintController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> WebReportPrintViewController {
        WebReportPrintViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: WebReportPrintViewController, context: Context) {}
}

final class WebReportPrintViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let webView = WKWebView(frame: .zero)
    private var hasPresentedPrint = false

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        debugLog("Loading export URL:", url.absoluteString)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        webView.load(URLRequest(url: url))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasPresentedPrint else { return }
        hasPresentedPrint = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let printController = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "Report Export"
            printController.printInfo = info
            printController.printFormatter = webView.viewPrintFormatter()
            printController.present(animated: true)
        }
    }
}

struct ExportURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
