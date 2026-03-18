import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .regular { // iPad: sidebar + main content
            NavigationSplitView {
                ReportListView()
                    .navigationTitle("Reports")
            } detail: {
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
                            .navigationTitle("Reports")
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
            }
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
                        .navigationTitle("Reports")
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
        }
    }
}
