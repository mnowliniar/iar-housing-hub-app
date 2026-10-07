import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    /// The sidebar layout is for a real iPad window. A Max phone turned
    /// sideways is also "regular" and keeps the tab bar.
    private var isPadLayout: Bool {
        hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        if isPadLayout {
            PadShell()
        } else { // iPhone: tab bar navigation
            TabView(selection: $app.selectedTab) {
                NavigationStack {
                    HomeView()
                        .navigationTitle("Home")
                }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

                NavigationStack {
                    ReportListView()
                }
                .tabItem {
                    Label("Reports", systemImage: "doc.text")
                }
                .tag(1)

                NavigationStack {
                    ChatView()
                        .navigationTitle("Spark")
                }
                .tabItem {
                    Label("Spark", systemImage: "sparkles")
                }
                .tag(2)
            }
            // Digest "Open" sets activeReport. Only the iPad branch presented
            // it, so on iPhone the button did nothing.
            .sheet(item: $app.activeReport) { active in
                NavigationStack {
                    ReportDetailView(report: active.report, geo: active.geo, updateDate: active.updateDate)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { app.activeReport = nil }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - iPad

/// What the sidebar can open. The three tab numbers the deep links and
/// notifications set (0 home, 1 reports, 2 spark) map onto the first three.
enum PadDestination: Hashable {
    case home
    case spark
    case reports
    case digest
    case pack
    case map
    case market(Int)

    var tab: Int? {
        switch self {
        case .home: return 0
        case .reports: return 1
        case .spark: return 2
        default: return nil
        }
    }

    static func from(tab: Int) -> PadDestination {
        switch tab {
        case 1: return .reports
        case 2: return .spark
        default: return .home
        }
    }
}

/// The iPad: a sidebar and one wide column, instead of the phone's tab bar
/// with the reports squeezed into a drawer. Home, Spark and Reports keep
/// the keyboard numbers; the member's markets sit under them so a market
/// is one tap from anywhere.
struct PadShell: View {
    @EnvironmentObject var app: AppState
    @State private var selection: PadDestination? = .home
    @State private var favorites: [Place] = []
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $app.activeReport) { active in
            NavigationStack {
                ReportDetailView(report: active.report, geo: active.geo, updateDate: active.updateDate)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { app.activeReport = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        // A deep link or a notification sets the phone's tab number; follow it.
        .onChange(of: app.selectedTab) { _, tab in
            let wanted = PadDestination.from(tab: tab)
            if selection != wanted { selection = wanted }
        }
        .onChange(of: selection) { _, picked in
            if let tab = picked?.tab, app.selectedTab != tab { app.selectedTab = tab }
        }
        .onChange(of: app.userPrefs.app.favoriteMarketIDs) { _, _ in
            Task { await loadFavorites() }
        }
        .task { await loadFavorites() }
        .background { keyboardShortcuts }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house").tag(PadDestination.home)
                Label { Text("Spark") } icon: { SparkMark(size: 18) }.tag(PadDestination.spark)
                Label("Reports", systemImage: "doc.text").tag(PadDestination.reports)
                Label("My Digest", systemImage: "envelope.open").tag(PadDestination.digest)
                Label("Market Pack", systemImage: "shippingbox").tag(PadDestination.pack)
                Label("Market Map", systemImage: "map").tag(PadDestination.map)
            }
            if !favorites.isEmpty {
                Section("Your markets") {
                    ForEach(favorites) { place in
                        Label(place.label, systemImage: "mappin").tag(PadDestination.market(place.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Housing Hub")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home:
            NavigationStack { HomeView() }
        case .spark:
            NavigationStack { ChatView() }
        case .reports:
            NavigationStack { ReportListView() }
        case .digest:
            NavigationStack { DigestView() }
        case .pack:
            NavigationStack { MarketPackView() }
        case .map:
            NavigationStack { MarketMapView() }
        case .market(let geoID):
            NavigationStack { MarketView(geoID: geoID) }
                .id(geoID)
        }
    }

    /// ⌘1, ⌘2, ⌘3 for the three main pages, as on the Mac. The buttons are
    /// not drawn; a keyboard shortcut works from anywhere in the window.
    private var keyboardShortcuts: some View {
        Group {
            Button("Home") { selection = .home }.keyboardShortcut("1", modifiers: .command)
            Button("Spark") { selection = .spark }.keyboardShortcut("2", modifiers: .command)
            Button("Reports") { selection = .reports }.keyboardShortcut("3", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func loadFavorites() async {
        for await top in PlacesService.top() {
            favorites = top.mine?.favorites ?? []
        }
    }
}
