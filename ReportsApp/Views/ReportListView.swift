import SwiftUI

struct ReportListView: View {
    var onViewReport: ((ActiveReport) -> Void)? = nil
    @EnvironmentObject var app: AppState
    @State private var reportsByCategory: [String: [Report]] = [:]
    @State private var showDigestLocal = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: DigestView()) {
                        Label("My Digest", systemImage: "bell.badge")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                ForEach(reportsByCategory.keys.sorted(), id: \.self) { category in
                    Section(header: Text(category)) {
                        ForEach(reportsByCategory[category] ?? []) { report in
                            NavigationLink(destination: ReportBuilderView(report: report, onViewReport: onViewReport)) {
                                ReportCardView(report: report)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select a Report")
            .background {
                NavigationLink(isActive: $showDigestLocal) {
                    DigestView()
                        .onDisappear { app.showDigest = false }
                } label: { EmptyView() }
                .hidden()
            }
            .onChange(of: app.showDigest) { _, newValue in
                if newValue { showDigestLocal = true }
            }
        }
        .onAppear {
            Task {
                reportsByCategory = await APIService.fetchReportsGrouped()
            }
        }
    }
}
