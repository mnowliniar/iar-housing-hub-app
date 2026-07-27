import SwiftUI

struct ReportDetailView: View {
    let report: Report
    let geo: Geo
    let updateDate: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ReportSummaryView(report: report, geo: geo, updateDate: updateDate)
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                EventTracker.fire(.viewReports, metadata: [
                    "report_id": String(report.id),
                    "geo_id": String(geo.geoid),
                    "surface": "ios_app",
                ])
            }
            .toolbar {
                if hSize == .regular {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            }
    }
}
