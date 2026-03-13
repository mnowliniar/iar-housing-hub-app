//
//  HomeView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//

// HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1) Dashboard section
                MarketDashboardView(geoID: app.selectedGeoID)

                // 1b) Favorite markets
                FavoriteMarketsRail()

                // 1c) Favorite reports
                FavoriteReportsRail()

                // 2) Blogs section
                BlogRail()
                // 3) Reports section
                ReportsRail()
            }
            .padding(.vertical, 4)
        }
        .background(
                LinearGradient(
                    colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
        .navigationTitle("Home")
    }
}

private func parseFavoriteIDs(_ raw: String) -> [Int] {
    raw
        .split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

private func encodeFavoriteIDs(_ ids: [Int]) -> String {
    ids.map(String.init).joined(separator: ",")
}

struct FavoriteMarketsRail: View {
    @EnvironmentObject var app: AppState
    @AppStorage("favoriteMarketIDs") private var favoriteMarketIDsRaw = ""
    @State private var geoLookup: [Int: Geo] = [:]
    @State private var showMarketPicker = false

    private var favoriteMarketIDs: [Int] {
        parseFavoriteIDs(favoriteMarketIDsRaw)
    }

    private var favoriteMarkets: [Geo] {
        favoriteMarketIDs.compactMap { geoLookup[$0] }
    }

    private var orderedFavoriteMarkets: [Geo] {
        guard let selectedGeoIDInt else { return favoriteMarkets }
        return favoriteMarkets.sorted { lhs, rhs in
            if lhs.geoid == selectedGeoIDInt { return true }
            if rhs.geoid == selectedGeoIDInt { return false }
            return false
        }
    }
    
    private var selectedGeoIDInt: Int? {
        Int(app.selectedGeoID)
    }

    private var activeGeo: Geo? {
        guard let selectedGeoIDInt else { return nil }
        return geoLookup[selectedGeoIDInt]
    }

    private var activeGeoName: String {
        activeGeo?.displayName ?? "Selected Market"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Favorite Markets")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        showMarketPicker = true
                    } label: {
                        Label("Add market", systemImage: "plus")
                            .font(.caption)
                    }
                    .disabled(favoriteMarketIDs.count >= 5)
                }
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(orderedFavoriteMarkets) { market in
                            FavoriteMarketCard(
                                market: market,
                                isSelected: market.geoid == selectedGeoIDInt,
                                onSelect: {
                                    app.selectedGeoID = String(market.geoid)
                                    DispatchQueue.main.async {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            proxy.scrollTo(market.geoid, anchor: .leading)
                                        }
                                    }
                                },
                                onRemove: { removeMarket(market.geoid) }
                            )
                            .id(market.geoid)
                        }

                        FavoriteMarketAddCard(
                            isDisabled: favoriteMarketIDs.count >= 5,
                            action: { showMarketPicker = true }
                        )
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                .onChange(of: app.selectedGeoID) { _, newValue in
                    if let id = Int(newValue) {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .leading)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadFavoriteGeos()
        }
        .sheet(isPresented: $showMarketPicker) {
            FavoriteMarketPickerSheet(
                existingIDs: favoriteMarketIDs,
                onSelect: { geo in
                    addMarket(geo)
                }
            )
        }
    }

    private func addMarket(_ geo: Geo) {
        var ids = favoriteMarketIDs
        guard !ids.contains(geo.geoid), ids.count < 5 else { return }
        ids.append(geo.geoid)
        favoriteMarketIDsRaw = encodeFavoriteIDs(ids)
        geoLookup[geo.geoid] = geo
        app.selectedGeoID = String(geo.geoid)
    }

    private func loadFavoriteGeos() async {
        let geotypes = await FavoriteGeoService.fetchGeoTypes()
        var merged: [Int: Geo] = [:]
        for type in geotypes {
            let geos = await FavoriteGeoService.fetchGeos(ofType: type)
            for geo in geos {
                if favoriteMarketIDs.contains(geo.geoid) || geo.geoid == selectedGeoIDInt {
                    merged[geo.geoid] = geo
                }
            }
        }
        await MainActor.run {
            geoLookup.merge(merged) { _, new in new }
        }
    }

    private func removeMarket(_ id: Int) {
        favoriteMarketIDsRaw = encodeFavoriteIDs(favoriteMarketIDs.filter { $0 != id })
        geoLookup.removeValue(forKey: id)
    }
}

struct FavoriteReportsRail: View {
    @EnvironmentObject var app: AppState
    @AppStorage("favoriteReportIDs") private var favoriteReportIDsRaw = ""
    @State private var latestReports: [ReportListItem] = []
    @State private var geoLookup: [Int: Geo] = [:]
    @State private var showReportPicker = false

    private var favoriteReportIDs: [Int] {
        parseFavoriteIDs(favoriteReportIDsRaw)
    }

    private var favoriteReports: [ReportListItem] {
        latestReports.filter { favoriteReportIDs.contains($0.report_id) }
    }

    private var selectedGeoIDInt: Int? {
        Int(app.selectedGeoID)
    }

    private var activeGeo: Geo? {
        guard let selectedGeoIDInt else { return nil }
        return geoLookup[selectedGeoIDInt]
    }

    private var activeGeoName: String {
        activeGeo?.displayName ?? "Selected Market"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favorite Reports")
                        .font(.headline)
                    Text("For \(activeGeoName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showReportPicker = true
                } label: {
                    Label("Pick reports", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(favoriteReports) { report in
                        FavoriteReportCard(
                            item: report,
                            selectedGeo: activeGeo,
                            onRemove: { removeReport(report.report_id) }
                        )
                    }

                    FavoriteReportAddCard(
                        isDisabled: favoriteReportIDs.count >= 3,
                        action: { showReportPicker = true }
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()

            NavigationLink {
                AllReportsListView(reports: latestReports, selectedGeo: activeGeo)
            } label: {
                Text("All reports for \(activeGeoName)")
                    .font(.subheadline)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal)
        }
        .task {
            do { latestReports = try await ReportsService.fetch(limit: 50) } catch { latestReports = [] }
            await loadFavoriteGeos()
        }
        .onChange(of: app.selectedGeoID) { _, _ in
            Task {
                await loadFavoriteGeos()
            }
        }
        .sheet(isPresented: $showReportPicker) {
            FavoriteReportPickerSheet(
                reports: latestReports,
                favoriteIDsRaw: $favoriteReportIDsRaw
            )
        }
    }

    private func loadFavoriteGeos() async {
        let geotypes = await FavoriteGeoService.fetchGeoTypes()
        var merged: [Int: Geo] = [:]
        for type in geotypes {
            let geos = await FavoriteGeoService.fetchGeos(ofType: type)
            for geo in geos {
                if geo.geoid == selectedGeoIDInt {
                    merged[geo.geoid] = geo
                }
            }
        }
        await MainActor.run {
            geoLookup.merge(merged) { _, new in new }
        }
    }

    private func removeReport(_ id: Int) {
        favoriteReportIDsRaw = encodeFavoriteIDs(favoriteReportIDs.filter { $0 != id })
    }
}

struct FavoriteMarketAddCard: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isDisabled ? .secondary : BrandColors.teal)
                Text("Add Favorite Market")
                    .font(.headline)
                Text("Choose up to five markets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .frame(width: 220, height: 110, alignment: .topLeading)
            .glassCard(cornerRadius: 12, tint: BrandColors.teal)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .opacity(isDisabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct FavoriteMarketCard: View {
    let market: Geo
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundStyle(BrandColors.teal)
                        Text(isSelected ? "Current Market" : market.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(market.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text("Tap to switch dashboard and reports to this market")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            .padding()
            .frame(width: 220, height: 110, alignment: .topLeading)
            .glassCard(cornerRadius: 12, tint: .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? BrandColors.teal : .clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct FavoriteReportAddCard: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isDisabled ? .secondary : BrandColors.teal)
                Text("Add Favorite Report")
                    .font(.headline)
                Text("Choose up to three reports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .frame(width: 220, height: 110, alignment: .topLeading)
            .glassCard(cornerRadius: 12, tint: BrandColors.teal)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .opacity(isDisabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct FavoriteReportCard: View {
    let item: ReportListItem
    let selectedGeo: Geo?
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let selectedGeo {
                    NavigationLink {
                        ReportSummaryView(
                            report: Report(id: item.report_id, title: item.title),
                            geo: selectedGeo,
                            updateDate: item.latestUpdateDate
                        )
                    } label: {
                        cardBody(subtitle: "Latest for \(selectedGeo.displayName)")
                    }
                } else {
                    cardBody(subtitle: "Select a market first")
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    @ViewBuilder
    private func cardBody(subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorite Report")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 220, height: 110, alignment: .topLeading)
        .glassCard(cornerRadius: 12, tint: .clear)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        .opacity(selectedGeo == nil ? 0.7 : 1)
    }
}

struct AllReportsListView: View {
    let reports: [ReportListItem]
    let selectedGeo: Geo?

    var body: some View {
        List(reports) { report in
            Group {
                if let selectedGeo {
                    NavigationLink {
                        ReportSummaryView(
                            report: Report(id: report.report_id, title: report.title),
                            geo: selectedGeo,
                            updateDate: report.latestUpdateDate
                        )
                    } label: {
                        AllReportsRow(report: report, subtitle: "Latest for \(selectedGeo.displayName)")
                    }
                } else {
                    AllReportsRow(report: report, subtitle: "Select a market first")
                }
            }
        }
        .navigationTitle(selectedGeo.map { "Reports for \($0.displayName)" } ?? "All Reports")
    }
}

struct AllReportsRow: View {
    let report: ReportListItem
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(report.report_date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct FavoriteReportPickerSheet: View {
    let reports: [ReportListItem]
    @Binding var favoriteIDsRaw: String

    @Environment(\.dismiss) private var dismiss

    private var favoriteIDs: [Int] {
        parseFavoriteIDs(favoriteIDsRaw)
    }

    var body: some View {
        NavigationStack {
            List(reports) { report in
                Button {
                    toggle(report.report_id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: favoriteIDs.contains(report.report_id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(favoriteIDs.contains(report.report_id) ? BrandColors.teal : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(report.report_date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Favorite Reports")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick up to three reports")
                        .font(.subheadline.weight(.semibold))
                    Text("These cards will always launch the latest version for your selected favorite market.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.thinMaterial)
            }
        }
    }

    private func toggle(_ id: Int) {
        var ids = favoriteIDs
        if ids.contains(id) {
            ids.removeAll { $0 == id }
        } else if ids.count < 3 {
            ids.append(id)
        }
        favoriteIDsRaw = encodeFavoriteIDs(ids)
    }
}
// --- Blog rail (cards share dash style)
struct Blog: Decodable, Identifiable {
    var id: String { slug }
    let title: String
    let thumbnail: String?
    let slug: String
    let blurb: String?
    let pinned: Bool?
}

final class BlogService {
    static func fetch() async throws -> [Blog] {
        let url = URL(string: "https://data.indianarealtors.com/api/research")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let root = try JSONDecoder().decode([String:[Blog]].self, from: data) // { "gresults": [...] }
        return root["gresults"] ?? []
    }
}

struct BlogRail: View {
    @State private var items: [Blog] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Blogs").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if loading {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.15))
                                .frame(width: 260, height: 400)
                        }
                    } else {
                        ForEach(items) { b in BlogCard(blog: b) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .task {
            do { items = try await BlogService.fetch() } catch { items = [] }
            loading = false
        }
    }
}

struct BlogCard: View {
    let blog: Blog

    var body: some View {
        let cardWidth: CGFloat = 260
        let cardPadding: CGFloat = 16
        let imageHeight: CGFloat = 140

        let thumbURL = absoluteURL(from: blog.thumbnail)
        let linkURL  = absoluteURL(from: blog.slug) ?? URL(string: "https://data.indianarealtors.com")!

        Link(destination: linkURL) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    // Image on top
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: cardWidth - (cardPadding * 2), height: imageHeight)
                                .clipped()
                        case .empty:
                            Rectangle()
                                .fill(.gray.opacity(0.15))
                                .frame(width: cardWidth - (cardPadding * 2), height: imageHeight)
                        case .failure:
                            Rectangle()
                                .fill(.gray.opacity(0.15))
                                .frame(width: cardWidth - (cardPadding * 2), height: imageHeight)
                        @unknown default:
                            Rectangle()
                                .fill(.gray.opacity(0.15))
                                .frame(width: cardWidth - (cardPadding * 2), height: imageHeight)
                        }
                    }
                    .frame(width: cardWidth - (cardPadding * 2), height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // Title
                    Text(blog.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    // Blurb
                    if let blurb = blog.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.caption)
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                if blog.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(6)
                }
            }
            .padding(cardPadding)
            .frame(width: cardWidth, height: 300, alignment: .topLeading)
            .glassCard(cornerRadius: 12)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func absoluteURL(from s: String?) -> URL? {
        guard let s = s, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: "https://data.indianarealtors.com" + s)
    }
}

// --- Reports rail (same card style) ---
struct ReportListItem: Decodable, Identifiable {
    let report_id: Int
    let title: String
    let report_date: String
    let update_date: String
    let thumbnail: String?
    var id: Int { report_id }
    var latestUpdateDate: String {
        String(update_date.prefix(10))
    }
}

final class ReportsService {
    static func fetch(limit: Int = 12) async throws -> [ReportListItem] {
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/reports/latest/")!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode([ReportListItem].self, from: data)
    }
}

struct ReportsRail: View {
    @State private var items: [ReportListItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Reports").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if loading {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.15))
                                .frame(width: 260, height: 100)
                        }
                    } else {
                        ForEach(items) { r in ReportCard(item: r) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .task {
            do { items = try await ReportsService.fetch() } catch { items = [] }
            loading = false
        }
    }
}

struct ReportCard: View {
    let item: ReportListItem
    @AppStorage("favoriteReportIDs") private var favoriteReportIDsRaw = ""

    private var isFavorite: Bool {
        parseFavoriteIDs(favoriteReportIDsRaw).contains(item.report_id)
    }

    private func toggleFavorite() {
        var ids = parseFavoriteIDs(favoriteReportIDsRaw)
        if ids.contains(item.report_id) {
            ids.removeAll { $0 == item.report_id }
        } else if ids.count < 3 {
            ids.append(item.report_id)
        }
        favoriteReportIDsRaw = encodeFavoriteIDs(ids)
    }

    private func formattedUpdate(_ s: String) -> String {
        // Expecting one of:
        //  - yyyy-MM-dd'T'HH:mm:ss
        //  - yyyy-MM-dd'T'HH:mm:ss.SSS
        //  - (optionally) with timezone suffix (e.g., Z or ±HH:mm)
        let posix = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone(secondsFromGMT: 0)

        var date: Date? = nil
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { date = d; break }
        }

        if let d = date {
            let out = DateFormatter()
            out.locale = posix
            out.timeZone = .current
            out.dateFormat = "MMM d 'at' h:mm a"
            return "Updated " + out.string(from: d)
        }

        // Fallback (shouldn't happen): show raw date with T replaced
        return "Updated " + s.replacingOccurrences(of: "T", with: " ")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                // Minimal Report stub to satisfy ReportBuilderView
                ReportBuilderView(report: Report(id: item.report_id, title: item.title))
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    // Dates
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.report_date)
                            .font(.caption)
                            .bold()
                        Text(formattedUpdate(item.update_date))
                            .font(.caption2)
                            .opacity(0.9)
                    }
                    // Title
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(width: 260, height: 100, alignment: .topLeading)
                .glassCard(cornerRadius: 12, tint: BrandColors.teal)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
        }
    }
}

// Convenience initializer so rails can construct a Report with minimal fields
extension Report {
    init(id: Int, title: String) {
        self.init(id: id, title: title, description: "", category: "", is_protected: false)
    }
}

extension View {
    @ViewBuilder
    func glassCard(
        cornerRadius: CGFloat = 12,
        tint: Color = .clear,
        tintOpacity: Double = 0.18,
        strokeOpacity: Double = 0.25
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                // Optional tint layer to nudge color toward brand
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                )
                // Subtle edge to match the glass look
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        } else {
            // Fallback for iOS < 18
            self
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        }
    }
}

final class FavoriteGeoService {
    static func fetchGeoTypes() async -> [String] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geotypes/") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("❌ Error fetching geo types: \(error)")
            return []
        }
    }

    static func fetchGeos(ofType type: String) async -> [Geo] {
        guard let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.indianarealtors.com/app/geos/?type=\(encodedType)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([Geo].self, from: data)
        } catch {
            print("❌ Error fetching geos: \(error)")
            return []
        }
    }
}

struct FavoriteMarketPickerSheet: View {
    let existingIDs: [Int]
    let onSelect: (Geo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var geotypes: [String] = []
    @State private var selectedType: String = ""
    @State private var geos: [Geo] = []
    @State private var selectedGeo: Geo?
    @State private var isLoadingTypes = true
    @State private var isLoadingGeos = false

    private var availableGeos: [Geo] {
        geos.filter { !existingIDs.contains($0.geoid) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Market type") {
                    if isLoadingTypes {
                        ProgressView()
                    } else {
                        Picker("Geo type", selection: $selectedType) {
                            ForEach(geotypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Market") {
                    if isLoadingGeos {
                        ProgressView()
                    } else if availableGeos.isEmpty {
                        Text("No markets available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Geo", selection: $selectedGeo) {
                            Text("Select a market").tag(nil as Geo?)
                            ForEach(availableGeos, id: \.self) { geo in
                                Text(geo.displayName).tag(Optional(geo))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
            }
            .navigationTitle("Add Favorite Market")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let selectedGeo {
                            onSelect(selectedGeo)
                            dismiss()
                        }
                    }
                    .disabled(selectedGeo == nil)
                }
            }
            .task {
                if geotypes.isEmpty {
                    await loadTypes()
                }
            }
            .onChange(of: selectedType) { _, newValue in
                Task { await loadGeos(for: newValue) }
            }
        }
    }

    private func loadTypes() async {
        isLoadingTypes = true
        let fetched = await FavoriteGeoService.fetchGeoTypes()

        let nextType: String = {
            if fetched.contains(selectedType) && !selectedType.isEmpty {
                return selectedType
            }
            return fetched.first ?? ""
        }()

        await MainActor.run {
            geotypes = fetched
            selectedType = nextType
            isLoadingTypes = false
        }

        if !nextType.isEmpty {
            await loadGeos(for: nextType)
        }
    }

    private func loadGeos(for type: String) async {
        guard !type.isEmpty else { return }

        let previousSelectionID = selectedGeo?.geoid

        await MainActor.run {
            isLoadingGeos = true
        }

        let fetched = await FavoriteGeoService.fetchGeos(ofType: type)
        let filtered = fetched.filter { !existingIDs.contains($0.geoid) }
        let restoredSelection = filtered.first(where: { $0.geoid == previousSelectionID })

        await MainActor.run {
            geos = fetched
            selectedGeo = restoredSelection
            isLoadingGeos = false
        }
    }
}
