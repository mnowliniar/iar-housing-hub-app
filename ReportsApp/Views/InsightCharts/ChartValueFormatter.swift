import Foundation

struct ChartValueFormatter {

    static func isPercentLike(format: String?, unit: String?) -> Bool {
        let fmt = (format ?? "").lowercased()
        let unitLower = (unit ?? "").lowercased()

        return fmt.contains("%") ||
            fmt.contains("percent") ||
            fmt.contains("pct") ||
            unitLower.contains("%") ||
            unitLower.contains("percent") ||
            unitLower.contains("pct")
    }

    static func isCurrencyLike(format: String?, unit: String?) -> Bool {
        let fmt = (format ?? "").lowercased()
        let unitLower = (unit ?? "").lowercased()

        return fmt.contains("$") ||
            fmt.contains("currency") ||
            fmt.contains("dollar") ||
            fmt.contains("price") ||
            unitLower.contains("$") ||
            unitLower.contains("currency") ||
            unitLower.contains("dollar") ||
            unitLower.contains("price")
    }

    static func scale(_ value: Double, format: String?, unit: String?) -> Double {
        isPercentLike(format: format, unit: unit) ? value * 100.0 : value
    }

    static func label(_ value: Double, format: String?, unit: String?) -> String {
        if isCurrencyLike(format: format, unit: unit) {
            return compactCurrencyLabel(value)
        }

        if isPercentLike(format: format, unit: unit) {
            return "\(Int(value.rounded()))%"
        }

        let rounded = value.rounded()

        if abs(rounded) >= 1000 {
            return Int(rounded).formatted()
        }

        if rounded == floor(rounded) {
            return String(Int(rounded))
        }

        return String(format: "%.1f", rounded)
    }

    private static func compactCurrencyLabel(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""

        if absValue >= 1_000_000 {
            let millions = absValue / 1_000_000
            if millions >= 10 {
                return "\(sign)$\(Int(millions.rounded()))M"
            } else {
                return "\(sign)$\(String(format: "%.1f", millions))M"
            }
        }

        if absValue >= 10_000 {
            let thousands = absValue / 1_000
            return "\(sign)$\(Int(thousands.rounded()))k"
        }

        return "\(sign)$\(Int(absValue.rounded()).formatted())"
    }
}
