import Foundation

struct ReportDate: Identifiable, Decodable, Hashable {
    let report_date: String         // e.g. "July 2025" (display)
    let update_date_only: String    // e.g. "2025-07-07" (value to pass)

    // Use update_date_only as unique ID
    var id: String { update_date_only }

    var displayName: String {
        report_date
    }
}
