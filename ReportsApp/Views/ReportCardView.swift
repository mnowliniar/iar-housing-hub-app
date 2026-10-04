import SwiftUI

/// One report in the list: what it is, how often it comes, when it last did.
struct ReportCardView: View {
    let report: Report
    @EnvironmentObject var app: AppState

    private var isFavorite: Bool { app.userPrefs.app.favoriteReportIDs.contains(report.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let meta = report.metaLine {
                    Text(meta.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                }
                Text(report.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if !report.description.isEmpty {
                    Text(report.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let edition = report.latest_report_date, !edition.isEmpty {
                    Text("Latest: \(edition)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(isFavorite ? BrandColors.teal : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                if report.is_protected {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func toggleFavorite() {
        var ids = app.userPrefs.app.favoriteReportIDs
        if let i = ids.firstIndex(of: report.id) {
            ids.remove(at: i)
        } else {
            ids.append(report.id)
            EventTracker.fire(.favoriteReports, metadata: ["report_id": String(report.id), "report_title": report.title])
        }
        app.userPrefs.app.favoriteReportIDs = ids
        app.saveUserPrefs()
    }
}
