import Foundation

struct DigestResponse: Decodable {
    let userEmail: String
    let subscriptions: [SubscriptionGroup]
    let digest: [DigestGroup]

    enum CodingKeys: String, CodingKey {
        case userEmail = "user_email"
        case subscriptions
        case digest
    }
}

struct SubscriptionGroup: Decodable, Identifiable {
    let reportID: Int
    let reportTitle: String
    let markets: [SubscriptionMarket]

    var id: Int { reportID }

    enum CodingKeys: String, CodingKey {
        case reportID = "report_id"
        case reportTitle = "report_title"
        case markets
    }
}

struct SubscriptionMarket: Decodable, Identifiable {
    let geoID: String
    let geoLabel: String
    let propertyType: String
    let updateDate: String?

    var id: String { "\(geoID)-\(propertyType)" }

    var formattedUpdateDate: String? {
        guard let updateDate else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss"] {
            df.dateFormat = fmt
            if let d = df.date(from: updateDate) {
                let out = DateFormatter()
                out.locale = posix
                out.timeZone = .current
                out.dateFormat = "MMM d"
                return "Updated \(out.string(from: d))"
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case geoID = "geo_id"
        case geoLabel = "geo_label"
        case propertyType = "property_type"
        case updateDate = "update_date"
    }
}

struct DigestGroup: Decodable, Identifiable {
    let date: String
    /// "yyyy-MM-dd". Newer servers send it; older ones only send `date`.
    let dateISO: String?
    let reports: [DigestReportEntry]

    var id: String { date }

    /// The report update date in the "yyyy-MM-dd" form the report summary
    /// endpoint takes. Falls back to parsing the display date
    /// ("September 17, 2026") when the server doesn't send `date_iso`.
    var updateDate: String? {
        if let dateISO, !dateISO.isEmpty { return dateISO }
        let posix = Locale(identifier: "en_US_POSIX")
        let input = DateFormatter()
        input.locale = posix
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.dateFormat = "MMMM d, yyyy"
        guard let d = input.date(from: date) else { return nil }
        let output = DateFormatter()
        output.locale = posix
        output.timeZone = TimeZone(secondsFromGMT: 0)
        output.dateFormat = "yyyy-MM-dd"
        return output.string(from: d)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case dateISO = "date_iso"
        case reports
    }
}

struct DigestReportEntry: Decodable, Identifiable {
    let reportID: Int
    let title: String
    let markets: [DigestMarket]

    var id: Int { reportID }

    enum CodingKeys: String, CodingKey {
        case reportID = "id"
        case title
        case markets
    }
}

struct DigestMarket: Decodable, Identifiable {
    let geoID: String
    let label: String
    let proptype: String
    let subscribed: Bool
    let vizCount: Int
    let vizTotal: Int

    var id: String { "\(geoID)-\(proptype)" }

    var geoIDInt: Int? { Int(geoID) }

    enum CodingKeys: String, CodingKey {
        case geoID = "geo_id"
        case label
        case proptype
        case subscribed
        case vizCount = "viz_count"
        case vizTotal = "viz_total"
    }
}
