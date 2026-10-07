//
//  MapLayerService.swift
//  ReportsApp
//
//  The Market Map's layers: the same GeoJSON files the web map reads from
//  Spaces, one per place type, indicator and period, with every county, ZIP
//  or township's value, last year's value and the change between them.
//

import Foundation
import MapKit
import UIKit

enum MapGeo: String, CaseIterable, Identifiable {
    case county, zipcode, township

    var id: String { rawValue }

    var label: String {
        switch self {
        case .county: return "Counties"
        case .zipcode: return "ZIP Codes"
        case .township: return "Townships"
        }
    }

    var singular: String {
        switch self {
        case .county: return "County"
        case .zipcode: return "ZIP Code"
        case .township: return "Township"
        }
    }

    /// The feature property that is also the Hub's geo id.
    var idKey: String {
        switch self {
        case .county: return "GEOID20"
        case .zipcode: return "ZCTA5CE10"
        case .township: return "iar_geoid"
        }
    }

    var nameKey: String {
        switch self {
        case .county: return "NAME20"
        case .zipcode: return "ZCTA5CE10"
        case .township: return "NAME"
        }
    }
}

enum MapIndicator: String, CaseIterable, Identifiable {
    case sales, listings, price, pctlist, dom, pends, marketheat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sales: return "Closed Sales"
        case .listings: return "New Listings"
        case .price: return "Median Sale Price"
        case .pctlist: return "Pct. of List Price"
        case .dom: return "Days on Market"
        case .pends: return "Pendings"
        case .marketheat: return "Market Heat Index"
        }
    }

    var isCount: Bool { self == .sales || self == .listings || self == .pends }
    var allowsYoY: Bool { self != .marketheat }
}

enum MapPeriod: String, CaseIterable, Identifiable {
    case oneWeek = "1week"
    case threeWeekAvg = "3weekavg"
    case oneMonth = "1month"
    case threeMonth = "3month"
    case twelveMonth = "12month"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneWeek: return "1 week"
        case .threeWeekAvg: return "3-week avg."
        case .oneMonth: return "1 month"
        case .threeMonth: return "3 months"
        case .twelveMonth: return "12 months"
        }
    }

    var isWeekly: Bool { self == .oneWeek || self == .threeWeekAvg }
}

enum MapMetric: String, CaseIterable, Identifiable {
    case value, yoy
    var id: String { rawValue }
}

/// One county, ZIP or township on the map.
struct MapFeature: Identifiable {
    let id: String
    let geoid: Int
    let name: String
    let value: Double?
    let prev: Double?
    let yoy: Double?
    let mapstat: Double?
    let measureDate: String?
    let polygons: [MKPolygon]
    /// Anything else the file said about this place (the heat index's parts).
    let extras: [String: Double]

    var boundingRect: MKMapRect {
        polygons.dropFirst().reduce(polygons.first?.boundingMapRect ?? .null) { $0.union($1.boundingMapRect) }
    }

    /// Ray casting over the outer rings; holes are rare in these layers.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let p = MKMapPoint(coordinate)
        for polygon in polygons where polygon.boundingMapRect.contains(p) {
            let points = polygon.points()
            let n = polygon.pointCount
            guard n > 2 else { continue }
            var inside = false
            var j = n - 1
            for i in 0..<n {
                let a = points[i], b = points[j]
                if (a.y > p.y) != (b.y > p.y),
                   p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
            if inside { return true }
        }
        return false
    }
}

struct MapLayer {
    let geo: MapGeo
    let indicator: MapIndicator
    let period: MapPeriod
    let features: [MapFeature]

    var key: String { "\(geo.rawValue)-\(indicator.rawValue)-\(period.rawValue)" }
    var measureDate: String? { features.first(where: { $0.measureDate != nil })?.measureDate }
}

enum MapLayerService {
    static let base = "https://iar-housing-hub-files.nyc3.digitaloceanspaces.com/files/output/maps"

    static func url(geo: MapGeo, indicator: MapIndicator, period: MapPeriod) -> URL? {
        URL(string: "\(base)/\(geo.rawValue)-\(indicator.rawValue)-\(period.rawValue).json")
    }

    struct LoadError: Error {}

    /// The layer, from disk when the Hub's data hasn't moved. Parsing a
    /// statewide file is real work, so it happens off the main thread.
    static func load(geo: MapGeo, indicator: MapIndicator, period: MapPeriod) async throws -> MapLayer {
        guard let url = url(geo: geo, indicator: indicator, period: period),
              let data = await HubCache.data(url, family: .data) else { throw LoadError() }
        return try await Task.detached(priority: .userInitiated) {
            try parse(data, geo: geo, indicator: indicator, period: period)
        }.value
    }

    private static func parse(_ data: Data, geo: MapGeo, indicator: MapIndicator, period: MapPeriod) throws -> MapLayer {
        let objects = try MKGeoJSONDecoder().decode(data)
        var features: [MapFeature] = []
        for case let feature as MKGeoJSONFeature in objects {
            let props = feature.properties
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            var polygons: [MKPolygon] = []
            for shape in feature.geometry {
                if let polygon = shape as? MKPolygon {
                    polygons.append(polygon)
                } else if let multi = shape as? MKMultiPolygon {
                    polygons.append(contentsOf: multi.polygons)
                }
            }
            guard !polygons.isEmpty, let geoid = int(props[geo.idKey]) else { continue }
            var extras: [String: Double] = [:]
            for (key, raw) in props where key.hasSuffix("_value") || key.hasSuffix("_score") || key.hasPrefix("heat_") {
                if let v = double(raw) { extras[key] = v }
            }
            let name: String
            if geo == .zipcode {
                name = String(geoid)
            } else {
                name = (props[geo.nameKey] as? String) ?? String(geoid)
            }
            features.append(MapFeature(
                id: String(geoid), geoid: geoid, name: name,
                value: double(props["value"]), prev: double(props["prev"]),
                yoy: double(props["yoy"]), mapstat: double(props["mapstat"]),
                measureDate: props["measuredate"] as? String,
                polygons: polygons, extras: extras))
        }
        guard !features.isEmpty else { throw LoadError() }
        return MapLayer(geo: geo, indicator: indicator, period: period, features: features)
    }

    private static func double(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber { let v = n.doubleValue; return v.isFinite ? v : nil }
        if let s = raw as? String, let v = Double(s), v.isFinite { return v }
        return nil
    }

    private static func int(_ raw: Any?) -> Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }
}

// MARK: - Colors and words, the web map's

/// A color ramp over a domain, the web map's chroma scales redrawn.
struct MapScale {
    struct Stop { let at: Double; let color: UIColor }
    let stops: [Stop]

    var low: Double { stops.first?.at ?? 0 }
    var high: Double { stops.last?.at ?? 1 }

    init(_ stops: [(Double, String)]) {
        self.stops = stops.map { Stop(at: $0.0, color: UIColor(hex: $0.1)) }
    }

    func color(_ value: Double) -> UIColor {
        guard let first = stops.first, let last = stops.last else { return .gray }
        if value <= first.at { return first.color }
        if value >= last.at { return last.color }
        for i in 1..<stops.count where value <= stops[i].at {
            let a = stops[i - 1], b = stops[i]
            let t = b.at == a.at ? 0 : (value - a.at) / (b.at - a.at)
            return a.color.mixed(with: b.color, t)
        }
        return last.color
    }

    /// Evenly spaced samples for a legend bar.
    func samples(_ count: Int = 24) -> [UIColor] {
        (0..<count).map { color(low + (high - low) * Double($0) / Double(count - 1)) }
    }

    static let lightTeal = "cfe5e7"   // the web's 20%-alpha teal over white

    static func scale(for indicator: MapIndicator, metric: MapMetric, geo: MapGeo, period: MapPeriod) -> MapScale {
        if indicator == .marketheat {
            return MapScale([(-100, "0b4ea2"), (-95, "0b4ea2"), (-35, "5e93bf"), (0, "d9e3e8"),
                             (35, "c783a9"), (95, "a10f5f"), (100, "a10f5f")])
        }
        if metric == .yoy {
            return MapScale([(-0.3, "95215e"), (0, "ffffff"), (0.3, "00737e")])
        }
        switch indicator {
        case .price:
            return MapScale([(100_000, lightTeal), (300_000, "004b8b"), (500_000, "95215e")])
        case .pctlist:
            return MapScale([(0.9, lightTeal), (0.975, "004b8b"), (1.05, "95215e")])
        case .dom:
            return MapScale([(5, "95215e"), (17.5, "004b8b"), (30, lightTeal)])
        case .listings:
            let top = countTop(geo: geo, period: period)
            return MapScale([(0, "ffffff"), (top / 2, "ebb81f"), (top, "00737e")])
        default:
            let top = countTop(geo: geo, period: period)
            return MapScale([(0, "ffffff"), (top / 2, "e77c05"), (top, "95215e")])
        }
    }

    /// Where the count ramps top out, per place type and period.
    private static func countTop(geo: MapGeo, period: MapPeriod) -> Double {
        switch (geo, period) {
        case (.county, .oneMonth): return 300
        case (.county, .threeMonth): return 900
        case (.county, .twelveMonth): return 3600
        case (.county, _): return 80
        case (.zipcode, .oneMonth): return 75
        case (.zipcode, .threeMonth): return 200
        case (.zipcode, .twelveMonth): return 800
        case (.zipcode, _): return 20
        case (.township, .oneMonth): return 150
        case (.township, .threeMonth): return 500
        case (.township, .twelveMonth): return 1500
        case (.township, _): return 40
        }
    }
}

enum MapWords {
    /// The number as the map's legend and panel say it.
    static func value(_ v: Double, indicator: MapIndicator) -> String {
        switch indicator {
        case .price:
            if v >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
            return "$\(Int((v / 1000).rounded()))K"
        case .pctlist:
            return String(format: "%.1f%%", v * 100)
        case .dom:
            let n = Int(v.rounded())
            return "\(n) \(n == 1 ? "day" : "days")"
        case .marketheat:
            return "\(Int((v * 100).rounded()))"
        default:
            return NumberFormatter.localizedString(from: NSNumber(value: Int(v.rounded())), number: .decimal)
        }
    }

    static func yoy(_ v: Double) -> String {
        let pct = v * 100
        let sign = pct > 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, pct)
    }

    static func legendEnd(_ v: Double, indicator: MapIndicator, metric: MapMetric) -> String {
        if metric == .yoy { return "\(Int((v * 100).rounded()))%" }
        switch indicator {
        case .price: return "$\(Int((v / 1000).rounded()))K"
        case .pctlist: return "\(Int((v * 100).rounded()))%"
        default: return "\(Int(v.rounded()))"
        }
    }

    /// The heat index's relative bands, the Hub's words.
    static func heatBand(_ score100: Double) -> String {
        if score100 >= 30 { return "Much hotter than the state" }
        if score100 >= 10 { return "Hotter than the state" }
        if score100 > -10 { return "Near the state average" }
        if score100 > -30 { return "Cooler than the state" }
        return "Much cooler than the state"
    }

    /// "Sep. 30, 2026", from the file's measure date, as the web legend.
    static func date(_ raw: String?, period: MapPeriod) -> String? {
        guard let raw, let day = raw.split(separator: "T").first else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard var date = f.date(from: String(day)) else { return nil }
        date = date.addingTimeInterval(TimeInterval((period.isWeekly ? 7 : 1) * 86_400))
        let out = DateFormatter()
        out.dateFormat = period.isWeekly ? "MMM d, yyyy" : "MMMM yyyy"
        return period.isWeekly ? "Week ending \(out.string(from: date))" : out.string(from: date)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        let r = CGFloat((n >> 16) & 0xff) / 255
        let g = CGFloat((n >> 8) & 0xff) / 255
        let b = CGFloat(n & 0xff) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = min(max(t, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k,
                       blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }
}
