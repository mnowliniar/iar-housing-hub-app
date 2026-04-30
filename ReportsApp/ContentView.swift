import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showReportsDrawer = false

    var body: some View {
        if hSize == .regular { // iPad: overlay drawer for reports
            ZStack(alignment: .leading) {

                TabView(selection: $app.selectedTab) {
                    NavigationStack {
                        HomeView()
                            .navigationTitle("Home")
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        withAnimation {
                                            showReportsDrawer.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "sidebar.left")
                                    }
                                }
                            }
                    }
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0)

                    NavigationStack {
                        ChatView()
                            .navigationTitle("Spark")
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        withAnimation {
                                            showReportsDrawer.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "sidebar.left")
                                    }
                                }
                            }
                    }
                    .tabItem {
                        Label("Spark", systemImage: "sparkles")
                    }
                    .tag(2)
                }
                .fullScreenCover(item: $app.activeReport) { active in
                    NavigationStack {
                        ReportDetailView(report: active.report, geo: active.geo, updateDate: active.updateDate)
                    }
                }

                if showReportsDrawer {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showReportsDrawer = false
                            }
                        }
                }

                HStack(spacing: 0) {
                    if showReportsDrawer {
                        NavigationStack {
                            ReportListView(onViewReport: { active in
                                app.activeReport = active
                                withAnimation { showReportsDrawer = false }
                            })
                            .navigationTitle("Reports")
                            .environment(\.horizontalSizeClass, .compact)
                        }
                        .frame(width: 320)
                        .background(.regularMaterial)
                        .transition(.move(edge: .leading))
                    }

                    Spacer()
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
