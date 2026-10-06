//
//  WatchHereCard.swift
//  ReportsWatchApp Watch App
//
//  The doorstep number. Raise the wrist on the way up the walk and see the
//  ZIP you're standing in with its median price, days on market and homes
//  for sale. Location is on the wrist and hands are full; this is the one
//  thing only the watch can do.
//

import SwiftUI
import CoreLocation

struct HereNumber: Identifiable {
    let id: Int
    let label: String
    let value: String
    let change: String?
}

/// Three numbers for one place, from the same endpoint as the dashboard.
enum WatchNumbers {
    /// Median sale price (10), median days on market (9), homes for sale (6);
    /// when a ZIP has no monthly numbers, the weekly sale price (4), homes
    /// for sale (6) and closed sales (3).
    static func fetch(geoID: Int) async -> [HereNumber] {
        let monthly = await fetch(geoID: geoID, vizIDs: "10,9,6")
        if !monthly.isEmpty { return monthly }
        return await fetch(geoID: geoID, vizIDs: "4,6,3")
    }

    private static func fetch(geoID: Int, vizIDs: String) async -> [HereNumber] {
        var parts = URLComponents(string: "https://\(AppIdentity.hubHost)/api/viz_set/proptype/all")
        parts?.queryItems = [
            URLQueryItem(name: "geo_ids", value: String(geoID)),
            URLQueryItem(name: "viz_ids", value: vizIDs),
            URLQueryItem(name: "facts", value: "fact1,fact2,fact3"),
            URLQueryItem(name: "fmt", value: "nested"),
            URLQueryItem(name: "compose", value: "0"),
            URLQueryItem(name: "window", value: "1"),
            URLQueryItem(name: "order", value: "asc"),
        ]
        guard let url = parts?.url, let data = await HubCache.data(url, family: .data),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let vizzes = results.first?["viz"] as? [[String: Any]] else { return [] }
        var out: [HereNumber] = []
        for viz in vizzes {
            guard let id = viz["viz_id"] as? Int,
                  let rows = viz["rows"] as? [[String: Any]],
                  let facts = rows.last?["facts"] as? [String: Any] else { continue }
            let f2 = facts["fact2"] as? [String: Any]
            let f1 = facts["fact1"] as? [String: Any]
            let f3 = facts["fact3"] as? [String: Any]
            let value = (f2?["value"] as? String) ?? (f1?["value"] as? String) ?? ""
            guard !value.isEmpty else { continue }
            var change: String?
            if let v = f3?["value"] as? String, !v.isEmpty {
                change = v + ((f3?["label"] as? String).map { " " + $0.lowercased().replacingOccurrences(of: "year over year", with: "yr") } ?? "")
            }
            out.append(HereNumber(id: id, label: Self.shortTitle(viz["viz_title"] as? String ?? "", id: id),
                                  value: value, change: change))
        }
        return out
    }

    private static func shortTitle(_ title: String, id: Int) -> String {
        switch id {
        case 10: return "Median price"
        case 4: return "Sale price, wk"
        case 9: return "Days on market"
        case 6: return "Homes for sale"
        case 3: return "Closed, wk"
        default: return title
        }
    }
}

@MainActor
final class WatchHereFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus
    @Published var zip: String?
    @Published var placeName: String?
    @Published var place: Place?
    @Published var numbers: [HereNumber] = []
    @Published var looking = false
    @Published var noMarket = false
    /// The ZIP is known but the Hub didn't answer with numbers.
    @Published var failed = false

    private let manager = CLLocationManager()

    var authorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    override init() {
        status = .notDetermined
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func find() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorized {
            looking = true
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            if self.authorized {
                self.looking = true
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.resolve(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.looking = false
        }
    }

    private func resolve(_ location: CLLocation) async {
        defer { looking = false }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = marks?.first, let zip = mark.postalCode else { return }
        self.zip = zip
        placeName = mark.subLocality ?? mark.locality
        if place?.label.hasPrefix(zip) == true, !numbers.isEmpty { return }
        let found = await PlacesService.search(zip).first(where: { $0.type == "ZIP Code" && $0.label.hasPrefix(zip) })
        guard let found else {
            place = nil
            numbers = []
            noMarket = true
            return
        }
        noMarket = false
        place = found
        await loadNumbers()
    }

    func loadNumbers() async {
        guard let place else { return }
        failed = false
        looking = true
        defer { looking = false }
        numbers = await WatchNumbers.fetch(geoID: place.id)
        failed = numbers.isEmpty
    }
}

struct WatchHereCard: View {
    @StateObject private var finder = WatchHereFinder()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let zip = finder.zip, finder.authorized {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.caption2)
                    Text("You're in \(zip)").font(.caption).bold()
                    Spacer(minLength: 0)
                    if finder.looking { ProgressView().controlSize(.mini) }
                }
                .foregroundStyle(.tint)
                if let name = finder.placeName {
                    Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if finder.noMarket {
                    Text("The Hub has no market for this ZIP.").font(.caption2).foregroundStyle(.secondary)
                } else if finder.failed {
                    Button {
                        Task { await finder.loadNumbers() }
                    } label: {
                        Label("No answer from the Hub. Try again", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                } else if finder.numbers.isEmpty {
                    Text("Getting the numbers…").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(finder.numbers) { n in
                        HStack(alignment: .firstTextBaseline) {
                            Text(n.label).font(.caption2).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(n.value).font(.caption).bold().monospacedDigit()
                        }
                        if let change = n.change {
                            Text(change).font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            } else if finder.status == .denied || finder.status == .restricted {
                Label("Location is off for Housing Hub", systemImage: "location.slash")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button {
                    finder.find()
                } label: {
                    HStack(spacing: 6) {
                        if finder.looking { ProgressView().controlSize(.mini) } else { Image(systemName: "location") }
                        Text(finder.looking ? "Finding your ZIP…" : "Where am I?")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                Text("The numbers for the ZIP you're standing in.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .task {
            if finder.authorized { finder.find() }
        }
    }
}
