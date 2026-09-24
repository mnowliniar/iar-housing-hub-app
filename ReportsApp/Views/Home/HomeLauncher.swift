//
//  HomeLauncher.swift
//  ReportsApp
//
//  Home's launcher, laid out like the web's grouped sidebar: the reports this
//  member keeps opening, their markets and saved neighborhoods with a heat
//  word, and Spark shortcuts. The rows come from /app/home/, the same
//  builders the web sidebar uses; the dashboard stays above this.
//

import SwiftUI

// MARK: - Data

struct HomeHabit: Decodable, Identifiable {
    let title: String
    let sub: String?
    let url: String
    var id: String { url }
}

struct HomeHeat: Decodable {
    let value: Double?

    /// The web sidebar's words; the middle band gets none.
    var word: String? {
        guard let v = value else { return nil }
        if v >= 30 { return "HOT" }
        if v >= 10 { return "WARM" }
        if v > -10 { return nil }
        if v > -30 { return "COOL" }
        return "COLD"
    }
}

struct HomeMarket: Decodable, Identifiable {
    let geoid: Int
    let label: String
    let heat: HomeHeat?
    var id: Int { geoid }
}

struct HomeArea: Decodable, Identifiable {
    let name: String
    let url: String
    let heat: HomeHeat?
    var id: String { url }
}

@MainActor
final class HomeLauncherModel: ObservableObject {
    @Published var habits: [HomeHabit] = []
    @Published var markets: [HomeMarket] = []
    @Published var areas: [HomeArea] = []
    @Published var latestRun: SparkRun?
    @Published var topRecipe: SparkRecipe?
    @Published var loaded = false

    private struct HomePayload: Decodable {
        let habits: [HomeHabit]?
        let markets: [HomeMarket]?
        let areas: [HomeArea]?
    }

    func load() async {
        if let url = URL(string: "\(ChatManager.serverBaseURL)/app/home/")?.appendingChatUserID() {
            let reply = try? await URLSession.shared.data(for: .app(url))
            if let data = reply?.0,
               let payload = try? JSONDecoder().decode(HomePayload.self, from: data) {
                habits = payload.habits ?? []
                markets = payload.markets ?? []
                areas = payload.areas ?? []
            }
        }
        let runs = try? await SparkLibraryService.runs(limit: 5)
        if let runs {
            latestRun = runs.first(where: { $0.canOpen })
        }
        let list = try? await SparkLibraryService.recipes()
        if let list {
            topRecipe = list.recipes.max(by: { $0.uses < $1.uses })
        }
        loaded = true
    }

    func removeMarket(_ geoid: Int) {
        markets.removeAll { $0.geoid == geoid }
    }
}

// MARK: - View

struct HomeLauncherView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var model = HomeLauncherModel()
    @State private var showingMarketPicker = false
    @State private var webLink: HomeWebLink?
    @State private var openingArea: String?

    private struct HomeWebLink: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            reportsGroup
            marketsGroup
            sparkGroup
        }
        .padding(.horizontal)
        .task { await model.load() }
        .sheet(isPresented: $showingMarketPicker) {
            FavoriteMarketPickerSheet(existingIDs: app.userPrefs.app.favoriteMarketIDs) { geo in
                addMarket(geo)
                showingMarketPicker = false
            }
        }
        .sheet(item: $webLink) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    // MARK: Your reports

    private var reportsGroup: some View {
        LauncherGroup(title: "Your reports") {
            NavigationLink {
                ReportListView()
                    .environmentObject(app)
            } label: {
                Text("All").font(.subheadline)
            }
        } content: {
            if model.habits.isEmpty {
                NavigationLink {
                    ReportListView()
                        .environmentObject(app)
                } label: {
                    LauncherRow(icon: "square.stack.3d.up", tint: BrandColors.teal,
                                title: "Browse reports",
                                subtitle: model.loaded ? "Your go-to reports will show up here" : nil)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(model.habits.enumerated()), id: \.element.id) { index, habit in
                Button {
                    openHubPath(habit.url)
                } label: {
                    LauncherRow(icon: index == 0 ? "chart.bar.fill" : "chart.line.uptrend.xyaxis",
                                tint: BrandColors.teal, title: habit.title, subtitle: habit.sub,
                                emphasized: index == 0)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                DigestView()
                    .environmentObject(app)
            } label: {
                LauncherRow(icon: "envelope.open", tint: BrandColors.teal,
                            title: "My Digest", subtitle: "Favorite reports and markets")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Your markets

    private var marketsGroup: some View {
        LauncherGroup(title: "Your markets") {
            EmptyView()
        } content: {
            ForEach(model.markets) { market in
                NavigationLink {
                    MarketView(geoID: market.geoid)
                        .environmentObject(app)
                } label: {
                    LauncherRow(icon: "mappin", tint: .blue, title: market.label, heat: market.heat?.word)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        removeMarket(market.geoid)
                    } label: {
                        Label("Remove from your markets", systemImage: "minus.circle")
                    }
                }
            }
            ForEach(model.areas.prefix(3)) { area in
                Button {
                    Task { await openOnWeb(area.url, key: area.url) }
                } label: {
                    LauncherRow(icon: "map", tint: .blue, title: area.name, heat: area.heat?.word,
                                trailingProgress: openingArea == area.url)
                }
                .buttonStyle(.plain)
            }
            if app.userPrefs.app.favoriteMarketIDs.count < 5 {
                Button {
                    showingMarketPicker = true
                } label: {
                    LauncherRow(icon: "plus", tint: .blue, title: "Add a market")
                }
                .buttonStyle(.plain)
            }
            Button {
                Task { await openOnWeb("/market/?tab=hood", key: "hood") }
            } label: {
                LauncherRow(icon: "pencil.and.outline", tint: .blue, title: "Build a neighborhood",
                            trailingProgress: openingArea == "hood")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Spark

    private var sparkGroup: some View {
        LauncherGroup(title: "Spark") {
            EmptyView()
        } content: {
            if let run = model.latestRun, let thread = run.threadID {
                Button {
                    app.sparkThreadToOpen = thread
                    app.selectedTab = 2
                } label: {
                    LauncherRow(icon: "clock.arrow.circlepath", tint: .purple,
                                title: run.recipeName, subtitle: "Latest run · " + run.subtitle)
                }
                .buttonStyle(.plain)
            }
            if let recipe = model.topRecipe {
                Button {
                    app.recipeToRun = recipe
                    app.selectedTab = 2
                } label: {
                    LauncherRow(icon: "fork.knife", tint: .purple, title: "Run \(recipe.name)",
                                subtitle: recipe.subtitle)
                }
                .buttonStyle(.plain)
            }
            Button {
                app.selectedTab = 2
            } label: {
                LauncherRow(icon: "sparkles", tint: .purple, title: "Ask Spark",
                            subtitle: "Numbers, charts, posts and emails for your market")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    /// Opens a Hub path the app handles itself (a report), through the same
    /// route a universal link takes.
    private func openHubPath(_ path: String) {
        guard let url = URL(string: ChatManager.serverBaseURL + path) else { return }
        app.handleDeepLink(url)
    }

    /// Opens a web page the app has no screen for, signed in.
    private func openOnWeb(_ path: String, key: String) async {
        openingArea = key
        defer { openingArea = nil }
        let signedIn = try? await SparkLibraryService.webLink(path: path)
        if let signedIn {
            webLink = HomeWebLink(url: signedIn)
        } else if let plain = URL(string: ChatManager.serverBaseURL + path) {
            webLink = HomeWebLink(url: plain)
        }
    }

    private func addMarket(_ geo: Geo) {
        var ids = app.userPrefs.app.favoriteMarketIDs
        guard !ids.contains(geo.geoid), ids.count < 5 else { return }
        ids.append(geo.geoid)
        app.userPrefs.app.favoriteMarketIDs = ids
        app.saveUserPrefs()
        EventTracker.fire(.favoriteMarkets, metadata: ["geo_id": String(geo.geoid)])
        model.markets.append(HomeMarket(geoid: geo.geoid, label: geo.displayName, heat: nil))
        // The heat word comes from the server once the save has landed.
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await model.load()
        }
    }

    private func removeMarket(_ geoid: Int) {
        app.userPrefs.app.favoriteMarketIDs.removeAll { $0 == geoid }
        app.saveUserPrefs()
        model.removeMarket(geoid)
    }
}

// MARK: - Building blocks

/// A captioned group, like the web's .grp-cap over .grp.
private struct LauncherGroup<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory()
                    .foregroundStyle(BrandColors.teal)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

/// One launcher row: a tinted tile, a title and subtitle, an optional heat
/// word, and a chevron.
private struct LauncherRow: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var heat: String? = nil
    var emphasized: Bool = false
    var trailingProgress: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(emphasized ? .body.weight(.semibold) : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let heat {
                HeatPill(word: heat)
            }
            if trailingProgress {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// HOT / WARM / COOL / COLD, as on the web sidebar.
private struct HeatPill: View {
    let word: String

    private var color: Color {
        switch word {
        case "HOT": return Color(red: 0.62, green: 0.08, blue: 0.05)    // #9d140d
        case "WARM": return Color(red: 0.91, green: 0.49, blue: 0.02)   // #e77c05
        case "COOL": return Color(red: 0.30, green: 0.55, blue: 0.80)
        default: return Color(red: 0.0, green: 0.29, blue: 0.55)        // #004b8b
        }
    }

    var body: some View {
        Text(word)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
