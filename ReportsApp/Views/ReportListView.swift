import SwiftUI

struct ReportListView: View {
    var onViewReport: ((ActiveReport) -> Void)? = nil
    @State private var reportsByCategory: [String: [Report]] = [:]

    var body: some View {
        NavigationView {
            List {
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
        }
        .onAppear {
            Task {
                reportsByCategory = await APIService.fetchReportsGrouped()
            }
        }
    }
}
