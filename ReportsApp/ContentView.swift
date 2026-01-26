import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .regular { // iPad: sidebar + main content
            NavigationSplitView {
                // LEFT: your existing reports list as the picker
                ReportListView()
                    .navigationTitle("Reports")
            } detail: {
                // RIGHT: Home dashboard as main content
                HomeView()
                    .navigationTitle("Home")
            }
        } else { // iPhone: show Home first, link to reports
            NavigationStack {
                HomeView()
                    .navigationTitle("Home")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink("Reports") {
                                ReportListView()
                            }
                        }
                    }
            }
        }
    }
}
