import SwiftUI

struct ReportCardView: View {
    let report: Report

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(report.title).font(.headline)
                Text(report.description).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            if report.is_protected {
                Image(systemName: "lock.fill").foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}