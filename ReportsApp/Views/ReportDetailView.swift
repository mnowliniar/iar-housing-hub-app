import SwiftUI

struct ReportDetailView: View {
    let report: Report
    let geo: Geo
    let updateDate: String

    var body: some View {
        ReportSummaryView(report: report, geo: geo, updateDate: updateDate)
    }
}
