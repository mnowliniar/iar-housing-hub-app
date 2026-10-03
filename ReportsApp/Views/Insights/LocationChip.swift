//
//  LocationChip.swift
//  ReportsApp
//
//  The phone knows where the member is standing, and the Hub has insights
//  for every ZIP. Before permission: a small chip offering it. After: a
//  row, "You're in 46204", that opens that ZIP's market page. Nothing
//  shows when location is off or the ZIP isn't a Hub market.
//

import SwiftUI
import CoreLocation

struct HereGeo: Equatable {
    let geoid: Int
    let zip: String
    let place: String
}

@MainActor
final class LocationFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus
    @Published var here: HereGeo?
    @Published var looking = false

    private let manager = CLLocationManager()
    private static let cacheKey = "here_geo"

    var authorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    override init() {
        status = .notDetermined
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        here = Self.cached()
    }

    /// Asks for permission the first time; after that, for a location.
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

    /// The ZIP the member is in, as a Hub market.
    private func resolve(_ location: CLLocation) async {
        defer { looking = false }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first, let zip = placemark.postalCode else { return }
        if let cached = here, cached.zip == zip { return }
        let types = await APIService.fetchGeoTypes()
        guard let zipType = types.first(where: { $0.lowercased().contains("zip") }) else { return }
        let geos = await APIService.fetchGeos(ofType: zipType)
        guard let geo = geos.first(where: { $0.name == zip || $0.displayName.hasPrefix(zip) }) else {
            here = nil
            return
        }
        let place = placemark.subLocality ?? placemark.locality ?? geo.displayName
        here = HereGeo(geoid: geo.geoid, zip: zip, place: place)
        UserDefaults.standard.set(["geoid": geo.geoid, "zip": zip, "place": place] as [String: Any], forKey: Self.cacheKey)
    }

    private static func cached() -> HereGeo? {
        guard let raw = UserDefaults.standard.dictionary(forKey: cacheKey),
              let geoid = raw["geoid"] as? Int,
              let zip = raw["zip"] as? String,
              let place = raw["place"] as? String else { return nil }
        return HereGeo(geoid: geoid, zip: zip, place: place)
    }
}

struct LocationChip: View {
    @StateObject private var finder = LocationFinder()
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if finder.authorized, let here = finder.here {
                NavigationLink {
                    MarketView(geoID: here.geoid)
                        .environmentObject(app)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrandColors.teal)
                            .frame(width: 32, height: 32)
                            .background(BrandColors.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're in \(here.zip)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(here.place) · this ZIP's insights")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .hubCard(padding: 12)
                }
                .buttonStyle(.plain)
            } else if finder.status == .notDetermined || (finder.authorized && finder.looking) {
                Button {
                    finder.find()
                } label: {
                    HStack(spacing: 8) {
                        if finder.looking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "location")
                                .font(.caption.weight(.semibold))
                        }
                        Text(finder.looking ? "Finding your ZIP…" : "Use my location for insights where you are")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(BrandColors.teal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(HubStyle.card, in: Capsule())
                    .overlay(Capsule().stroke(BrandColors.teal.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            // Already allowed: refresh quietly on each visit to Home.
            if finder.authorized { finder.find() }
        }
    }
}
