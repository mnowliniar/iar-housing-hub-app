//
//  ReportSummaryView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 8/26/25.
//


import SwiftUI
import Charts

struct ReportSummaryView: View {
    let report: Report
    let geo: Geo
    let updateDate: String

    @State private var summary: ReportSummary?
    @State private var isLoading = true
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ScrollView {
            if let summary = summary {
                VStack(alignment: .leading, spacing: 12) {
                    // Title area
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.title2).bold()
                        Text(summary.geo)
                            .font(.subheadline).foregroundColor(.secondary)
                        Text(summary.report_date)
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Cards
                    ForEach(summary.vizzes) { viz in
                       Group {
                               // iPhone / compact: original stacked layout
                               VStack(alignment: .leading, spacing: 6) {
                                   // ABOVE CHART (title and big num)
                                   Text(viz.title).font(.headline).padding(.bottom, 6)
                                   if let label2 = viz.fact2label, let val2 = viz.fact2 {
                                       HeroFactRow(label: label2, value: val2, expected: viz.exp2)
                                   }
                                   // CHART
                                   if let url = viz.csvURL, let type = viz.type {
                                       DataChartView(
                                           csvURL: url,
                                           type: type,
                                           color: .blue,
                                           title: viz.title,
                                           format: viz.format ?? "default"
                                       )
                                       .onAppear { print("✅ Rendering chart for: \(viz.title) type: \(type)") }
                                       .padding(.top)
                                   }
                                   // BELOW CHART (supporting chips)
                                   Divider().padding(.vertical, 4)
                                   LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                                       if let label1 = viz.fact1label, let val1 = viz.fact1 {
                                           StatChip(label: label1, value: val1, expected: viz.exp1)
                                       }
                                       if let label3 = viz.fact3label, let val3 = viz.fact3 {
                                           StatChip(label: label3, value: val3, expected: viz.exp3)
                                       }
                                   }
                               }
                       }
                        .padding()
                        .glassCard()
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                        .padding(.horizontal)
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
        .background(
            LinearGradient(
                colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            print("Loading summary for \(geo.geoid), \(updateDate)")
            await loadSummary()
        }
    }

    func loadSummary() async {
        isLoading = true
        print("Calling APIService.fetchReportSummary")
        summary = await APIService.fetchReportSummary(
            reportID: report.id,
            updateDate: updateDate,
            geoID: geo.geoid
        )
        isLoading = false
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let expected: String?
    var tint: Color = BrandColors.teal

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).lineLimit(1).opacity(0.85)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.footnote.weight(.semibold)).lineLimit(1)
                if let expected = expected, !expected.isEmpty {
                    Text(expected)
                        .font(.caption2)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.7)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
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
    let csvURL: URL
    let type: String
    let color: Color
    let title: String
    let format: String

    struct Series: Identifiable {
        let id = UUID()
        let name: String
        var values: [Double]
    }

    struct DataPackage {
        var labels: [String] = []
        var dates: [Date]? = nil
        var series: [Series] = []
        var format: String = "default"
    }

    @State private var dataPackage = DataPackage()
    @State private var isLoading = true
    
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
        let range = domain.map { allColors[$0] ?? .accentColor }
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
                    AxisGridLine(); AxisTick()
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
                    AxisMarks(values: ticks) { AxisGridLine(); AxisTick(); AxisValueLabel().offset(y: 7) }
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
                ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                    let end: Int = {
                        if let ds = dates, !ds.isEmpty {
                            return Swift.min(labels.count, s.values.count, ds.count)
                        } else {
                            return Swift.min(labels.count, s.values.count)
                        }
                    }()
                    switch type {
                    case "barCat", "barGrouped":
                        // Categorical bars: ignore dates, use labels as x
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
                        // Lines: use dates when available, else categorical labels
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
                        // Terminal dot for all series
                        if let last = (0..<end).last(where: { i in
                            i < s.values.count && s.values[i].isFinite
                        }) {
                            if let ds = dates, last < ds.count {
                                PointMark(
                                    x: .value("Date", ds[last]),
                                    y: .value(s.name, s.values[last])
                                )
                                .symbol(.circle)
                                .symbolSize(30) // adjust size to taste
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
                        // End labels for trend overlays (match series color)
                        if type == "lineTrend" && s.name == "Last 3 weeks" {
                            // Find the last valid index within `end` for this series
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

    // --- Add yDomain helper:
    var yDomain: ClosedRange<Double> {
        let vals = dataPackage.series.flatMap { $0.values }.filter { !$0.isNaN && $0.isFinite }
        guard let loRaw = vals.min(), let hiRaw = vals.max(), loRaw.isFinite, hiRaw.isFinite else {
            return 0...1
        }
        // Bar chart types should start at zero for honest bar lengths
        let isBar = (type == "barCat" || type == "barGrouped" || type == "barWeek")
        let lo = isBar ? 0.0 : loRaw
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

                if type == "lineTrend" {
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
                                .frame(width: contentWidth, height: 200)

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
                    .chartLegend(.visible)
                    .chartYScale(domain: yDomain)
                    .frame(height: 200)
                }
            }
        }
        .task {
            await loadCSV(from: csvURL)
        }
    }

    func formatLabel(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        switch type {
        case "line", "lineYoy", "yoyExp":
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM yyyy"
            return fmt.string(from: date)
        case "lineDaily":
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        case "lineYr":
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy"
            return fmt.string(from: date)
        case "barWeek", "lineWeek":
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            return fmt.string(from: date)
        default:
            return dateString
        }
    }

    func loadCSV(from url: URL) async {
        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("text/csv, */*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue("ReportsApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                print("HTTP status: \(http.statusCode), mime: \(http.mimeType ?? "?"), length: \(data.count)")
            } else {
                print("Non-HTTP response, length: \(data.count)")
            }
            guard !data.isEmpty else {
                print("⚠️ Empty body from \(url.absoluteString)")
                return
            }

            // Decode with UTF-8, fall back to ISO Latin-1 if needed
            let csv: String
            if let s = String(data: data, encoding: .utf8) {
                csv = s
            } else if let s = String(data: data, encoding: .isoLatin1) {
                csv = s
            } else {
                print("⚠️ Failed to decode CSV as UTF-8/ISO-8859-1")
                return
            }
            print(csv.prefix(500))
            // Naive CSV split (sufficient for our defaults)
            let lines = csv.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            guard let headerLine = lines.first else { return }
            let headers = headerLine.components(separatedBy: ",")
            let rows = lines.dropFirst().map { $0.components(separatedBy: ",") }

            func index(_ name: String) -> Int? { headers.firstIndex(of: name) }
            func parseNumber(_ s: String) -> Double? {
                let cleaned = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return Double(cleaned)
            }

            // Labels: prefer "Reporting date" (formatted), else "x"
            let dateIdx = index("Reporting date")
            let xIdx = index("x")
            guard let labelIdx = xIdx ?? dateIdx else { return }

            var labels: [String] = []
            var dates: [Date]? = dateIdx != nil ? [] : nil
            labels.reserveCapacity(rows.count)
            for row in rows {
                guard row.count > labelIdx else { continue }
                let raw = row[labelIdx]
                if dateIdx != nil {
                    labels.append(formatLabel(raw))
                    // parse ISO "yyyy-MM-dd" into Date
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    if let d = df.date(from: raw) { dates?.append(d) }
                } else {
                    labels.append(raw)
                }
            }

            // SERIES FACTORY + DETECTOR (systematic, supports infinite series)
            func makeSeries(name: String, idx: Int) -> Series {
                var vals: [Double] = []
                vals.reserveCapacity(rows.count)
                for row in rows {
                    if row.indices.contains(idx), let d = parseNumber(row[idx]) {
                        vals.append(d)
                    } else {
                        vals.append(.nan)
                    }
                }
                return Series(
                    name: name,
                    values: vals
                )
            }

            func firstNonEmpty(inColumn nameCol: String) -> String? {
                guard let cIdx = index(nameCol) else { return nil }
                for r in rows {
                    if r.indices.contains(cIdx) {
                        let v = r[cIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !v.isEmpty { return v }
                    }
                }
                return nil
            }

            func seriesPlan(for headers: [String]) -> SeriesPlan {
                switch type {
                    
                case "barCat", "barGrouped":
                    if let xIdx = index("x"), let yIdx = index("y") {
                        let labels = rows.compactMap { row in
                            row.indices.contains(xIdx) ? row[xIdx] : nil
                        }
                        let values = rows.compactMap { row in
                            row.indices.contains(yIdx) ? parseNumber(row[yIdx]) : nil
                        }
                        let s = Series(name: "Current", values: values)
                        var pkg = DataPackage()
                        pkg.labels = labels
                        pkg.series = [s]
                        pkg.format = format.isEmpty ? "default" : format
                        DispatchQueue.main.async {
                            self.dataPackage = pkg
                            self.isLoading = false
                        }
                        return .built([s])
                    }
                    fallthrough
                    
                case "lineWeek", "barWeek":
                    var cols: [(String, Int)] = []
                    if let a = index("Estimated weekly value") {
                        cols.append(("Current", a))
                    }
                    if !cols.isEmpty { return .columns(cols) }
                    fallthrough

                case "yoyExp", "line3mo", "line12mo", "line", "lineYr":
                    var cols: [(String, Int)] = []
                    if let a = index("Value") { cols.append(("Current", a)) }
                    if let i = index("Value (previous year)") { cols.append(("Previous Year", i)) }
                    if !cols.isEmpty { return .columns(cols) }
                    fallthrough

                case "lineComp":
                    var cols: [(String, Int)] = []
                    if let a = index("Value (This Area)") ?? index("Value (Selected Area)") {
                        cols.append(("Selected Area", a))
                    }
                    if let i = index("Value (Indiana)") {
                        cols.append(("Indiana", i))
                    }
                    if !cols.isEmpty { return .columns(cols) }
                    fallthrough

                case "lineTrend":
                    // Build directly here: pick ONE baseline series, then append the four trend overlays
                    let baseIdx: Int? = index("Estimated weekly value") ?? index("Value") ?? index("y1") ?? index("y")
                    if let bIdx = baseIdx {
                        // Base name from y1name/yname if present
                        let baseName: String = {
                            if bIdx == index("y1"), let nm = firstNonEmpty(inColumn: "y1name") { return nm }
                            if bIdx == index("y"),  let nm = firstNonEmpty(inColumn: "yname")  { return nm }
                            return "Weekly"
                        }()
                        let base = makeSeries(name: baseName, idx: bIdx)
                        let v = base.values
                        let n = v.count

                        func mean(_ xs: ArraySlice<Double>) -> Double? {
                            let vals = xs.filter { !$0.isNaN }
                            guard !vals.isEmpty else { return nil }
                            return vals.reduce(0, +) / Double(vals.count)
                        }
                        func safeSlice(_ start: Int, _ end: Int) -> ArraySlice<Double>? {
                            let s = max(0, start), e = min(n, end)
                            return (s < e) ? v[s..<e] : nil
                        }
                        // Replacement for repLine: overlay only in window, NaN elsewhere
                        func windowLine(_ value: Double?, start: Int, end: Int, count: Int) -> [Double]? {
                            guard let v = value else { return nil }
                            var arr = Array(repeating: Double.nan, count: count)
                            let s = max(0, start)
                            let e = min(count, end)
                            if s < e {
                                for i in s..<e { arr[i] = v }
                            }
                            return arr
                        }

                        // Your exact windows
                        let recentAvg      = safeSlice(n-3,     n).flatMap(mean)
                        let previousAvg    = safeSlice(n-9,   n-3).flatMap(mean)
                        let yoyRecentAvg   = safeSlice(n-3-52, n-52).flatMap(mean)
                        let yoyPreviousAvg = safeSlice(n-9-52, n-3-52).flatMap(mean)

                        var built: [Series] = [base]
                        if let line = windowLine(recentAvg, start: n-3, end: n, count: n) {
                            built.append(Series(name: "Last 3 weeks", values: line))
                        }
                        if let line = windowLine(previousAvg, start: n-9, end: n-3, count: n) {
                            built.append(Series(name: "Prior 6 weeks", values: line))
                        }
                        if let line = windowLine(yoyRecentAvg, start: n-3-52, end: n-52, count: n) {
                            built.append(Series(name: "YoY Recent", values: line))
                        }
                        if let line = windowLine(yoyPreviousAvg, start: n-9-52, end: n-3-52, count: n) {
                            built.append(Series(name: "YoY Previous", values: line))
                        }
                        return .built(built)
                    }
                    fallthrough

                case "dotPlot":
                    var cols: [(String, Int)] = []
                    var n = 1
                    while let yIdx = index("y\(n)") {
                        let suggested = firstNonEmpty(inColumn: "y\(n)name") ?? "Series \(n)"
                        cols.append((suggested, yIdx))
                        n += 1
                    }
                    if !cols.isEmpty { return .columns(cols) }
                    if let y = index("y")  { cols.append((firstNonEmpty(inColumn: "yname")  ?? "Current",    y)) }
                    if let y2 = index("y2"){ cols.append((firstNonEmpty(inColumn: "y2name") ?? "Comparison", y2)) }
                    if !cols.isEmpty { return .columns(cols) }
                    fallthrough

                default:
                    var cols: [(String, Int)] = []
                    if let v = index("Value") { cols.append(("Value", v)) }
                    var n = 1
                    while let yIdx = index("y\(n)") {
                        let suggested = firstNonEmpty(inColumn: "y\(n)name") ?? "Series \(n)"
                        cols.append((suggested, yIdx))
                        n += 1
                    }
                    if cols.isEmpty, let y = index("y") { cols.append(("Current", y)) }
                    if let y2 = index("y2") { cols.append(("Comparison", y2)) }
                    return .columns(cols)
                }
            }
            
            enum SeriesPlan {
                case columns([(String, Int)])   // use factory later
                case built([Series])            // already built here (e.g., lineTrend)
            }
            let plan = seriesPlan(for: headers)
            let built: [Series]
            switch plan {
            case .columns(let cols):
                built = cols.map { makeSeries(name: $0.0, idx: $0.1) }
            case .built(let s):
                built = s
            }
            var pkg = DataPackage()
            pkg.labels = labels
            pkg.dates = dates
            pkg.series = built
            pkg.format = format.isEmpty ? "default" : format

            DispatchQueue.main.async {
                self.dataPackage = pkg
                self.isLoading = false
            }
            return
        } catch {
            print("Error loading CSV: \(error)")
        }
    }
}
