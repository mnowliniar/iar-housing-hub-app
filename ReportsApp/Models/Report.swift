import Foundation

struct Report: Identifiable, Decodable {
    let id: Int
    let title: String
    let description: String
    let category: String
    let is_protected: Bool
    /// "Weekly", "Monthly", … when the Hub can tell.
    var cadence: String? = nil
    /// The latest edition's label, like "Week of Sep 29".
    var latest_report_date: String? = nil
    /// When that edition was built, ISO 8601.
    var latest_update: String? = nil

    /// "Weekly · updated Oct 2", or whichever half the Hub knows.
    var metaLine: String? {
        var bits: [String] = []
        if let cadence, !cadence.isEmpty { bits.append(cadence) }
        if let day = Report.shortDay(latest_update) { bits.append("updated \(day)") }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    static func shortDay(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(iso.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }
}
