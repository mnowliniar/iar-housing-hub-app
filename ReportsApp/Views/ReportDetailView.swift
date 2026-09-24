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
            .toolbar {
                if hSize == .regular {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            }
    }
}
