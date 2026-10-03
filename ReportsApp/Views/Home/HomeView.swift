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
    @EnvironmentObject var auth: AuthManager
    @State private var showDeepLinkedInsights = false

    /// A market page opened from a universal link.
    private var showLinkedMarket: Binding<Bool> {
        Binding(get: { app.marketGeoID != nil },
                set: { if !$0 { app.marketGeoID = nil } })
    }

    @State private var showGeoPicker = false
    @State private var showSettings = false
    @State private var dashboardGeo: Geo?

    /// The market the numbers at the top are for.
    private var dashboardGeoID: String {
        let id = app.userPrefs.app.dashboardGeoID ?? ""
        return id.isEmpty ? "18" : id
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if auth.needsFreshSignIn {
                    FreshSignInCard()
                }

                // The week's numbers as one strip, so the insight under it
                // is on screen without scrolling.
                MarketDashboardView(geoID: app.selectedGeoID)

                InsightRail(geoID: dashboardGeoID)

                LocationChip()
                    .padding(.horizontal)

                HomeLauncherView()

                BlogRail()
                ReportsRail()
            }
            .padding(.vertical, 4)
            .padding(.bottom, 12)
        }
        .hubPage()
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGeoPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(dashboardGeo?.displayName ?? "Market")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .accessibilityLabel("Change the dashboard market")
            }
        }
        .task(id: dashboardGeoID) {
            dashboardGeo = await APIService.fetchGeo(geoid: dashboardGeoID)
        }
        .sheet(isPresented: $showGeoPicker) {
            GeoPickerSheet { newGeo in
                app.selectedGeoID = newGeo
                app.userPrefs.app.dashboardGeoID = newGeo
                app.saveUserPrefs()
                showGeoPicker = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .background {
            NavigationLink(isActive: $showDeepLinkedInsights) {
                InsightsView(geoID: Int(app.insightGeoID ?? app.selectedGeoID) ?? 18)
                    .environmentObject(app)
                    .onDisappear {
                        app.insightGeoID = nil
                        showDeepLinkedInsights = false
                    }
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onChange(of: app.insightGeoID) { _, newValue in
            showDeepLinkedInsights = (newValue != nil)
        }
        .navigationDestination(isPresented: showLinkedMarket) {
            if let geo = app.marketGeoID.flatMap(Int.init) {
                MarketView(geoID: geo)
                    .environmentObject(app)
            }
        }
    }
}


/// Shown when the server can't tell whose sign-in this is (it predates the
/// app naming the member and couldn't be repaired). One tap signs in
/// again in place; with Safari still holding the member's login it takes
/// a moment and asks nothing.
private struct FreshSignInCard: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.title3)
                .foregroundStyle(BrandColors.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("One more sign-in")
                    .font(.subheadline.weight(.semibold))
                Text("The update needs it for recipes, schedules and the web pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign in") { auth.signInAgain() }
                .buttonStyle(.borderedProminent)
                .tint(BrandColors.teal)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
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
        let (data, _) = try await URLSession.shared.data(for: .app(url))
        let root = try JSONDecoder().decode([String:[Blog]].self, from: data) // { "gresults": [...] }
        return root["gresults"] ?? []
    }
}

struct BlogRail: View {
    @State private var items: [Blog] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Latest blogs").padding(.horizontal)
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
            .frame(width: cardWidth, alignment: .topLeading)
            .frame(minHeight: 300, alignment: .topLeading)
            .glassCard(cornerRadius: 12)
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
        let (data, _) = try await URLSession.shared.data(for: .app(comps.url!))
        return try JSONDecoder().decode([ReportListItem].self, from: data)
    }
}

struct ReportsRail: View {
    @State private var items: [ReportListItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Latest reports").padding(.horizontal)
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
    @EnvironmentObject var app: AppState
    @State private var showNotificationRationale = false
    @ScaledMetric(relativeTo: .headline) private var cardWidth: CGFloat = 260

    private var isFavorite: Bool {
        app.userPrefs.app.favoriteReportIDs.contains(item.report_id)
    }

    private func toggleFavorite() {
        var ids = app.userPrefs.app.favoriteReportIDs
        let wasAdding = !ids.contains(item.report_id)
        if ids.contains(item.report_id) {
            ids.removeAll { $0 == item.report_id }
        } else if ids.count < 3 {
            ids.append(item.report_id)
        }
        app.userPrefs.app.favoriteReportIDs = ids
        app.saveUserPrefs()
        if wasAdding, ids.contains(item.report_id) {
            EventTracker.fire(.favoriteReports, metadata: ["report_id": String(item.report_id)])
        }
        if wasAdding {
            NotificationScheduler.isUndetermined { undetermined in
                if undetermined {
                    showNotificationRationale = true
                } else {
                    NotificationScheduler.requestAndSchedule()
                }
            }
        }
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
                .frame(width: cardWidth, alignment: .topLeading)
                .frame(minHeight: 100, alignment: .topLeading)
                .glassCard(cornerRadius: 12, tint: BrandColors.teal)
            }
            .buttonStyle(.plain)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showNotificationRationale) {
            NotificationRationaleSheet(isPresented: $showNotificationRationale)
                .presentationDetents([.medium])
        }
    }
}

private struct NotificationRationaleSheet: View {
    @Binding var isPresented: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 52

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: iconSize))
                .foregroundStyle(BrandColors.teal)

            VStack(spacing: 10) {
                Text("Stay on Top of Your Markets")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("We'll send you a reminder every Thursday and on the 7th of each month so you never miss a digest update.\n\nTap **Allow** when iOS asks.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    isPresented = false
                    NotificationScheduler.requestAndSchedule()
                } label: {
                    Text("Enable Notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BrandColors.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button("Not Now") {
                    isPresented = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
    }
}

// Convenience initializer so rails can construct a Report with minimal fields
extension Report {
    init(id: Int, title: String) {
        self.init(id: id, title: title, description: "", category: "", is_protected: false)
    }
}

extension View {
    /// The one card: white, a hairline, a soft shadow, like the insight
    /// card. The glass effect and the tints are gone; the parameters stay
    /// so call sites didn't have to change.
    func glassCard(
        cornerRadius: CGFloat = 16,
        tint: Color = .clear,
        tintOpacity: Double = 0.18,
        strokeOpacity: Double = 0.25
    ) -> some View {
        self
            .background(HubStyle.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HubStyle.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

final class FavoriteGeoService {
    static func fetchGeoTypes() async -> [String] {
        guard let url = URL(string: "https://data.indianarealtors.com/app/geotypes/") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(for: .app(url))
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            debugLog("❌ Error fetching geo types: \(error)")
            return []
        }
    }

    static func fetchGeos(ofType type: String) async -> [Geo] {
        guard let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://data.indianarealtors.com/app/geos/?type=\(encodedType)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(for: .app(url))
            return try JSONDecoder().decode([Geo].self, from: data)
        } catch {
            debugLog("❌ Error fetching geos: \(error)")
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


/// Account and app details. Sign out lives here now, off the Home page.
private struct SettingsSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Signed in as", value: UserDefaults.standard.string(forKey: "chat_user_id") ?? "Member")
                    Button("Sign out", role: .destructive) {
                        dismiss()
                        auth.logout()
                    }
                }
                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
