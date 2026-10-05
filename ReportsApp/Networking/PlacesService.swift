//
//  PlacesService.swift
//  ReportsApp
//
//  The one place endpoint, /api/places/, and the shapes it returns. Shared
//  by the phone's picker and the watch's.
//

import Foundation

struct Place: Decodable, Identifiable, Hashable {
    let id: Int
    let label: String
    let type: String
    let sub: String?
    let parent: String?
    let households: Int?
    let protected: Bool?
    let heat: PlaceHeat?

    /// The app's Geo, for every screen that already takes one.
    var geo: Geo {
        Geo(geoid: id, type: type, name: label, label: label, households: households ?? 0)
    }

    /// Two or three letters for the row's badge.
    var badge: String {
        switch type {
        case "State": return "ST"
        case "County": return "CO"
        case "ZIP Code": return "ZIP"
        case "Township": return "TWP"
        case "Metro Area", "CBSA": return "MET"
        case "Association": return "AS"
        case "MLS": return "MLS"
        case "City", "Town", "Place": return "CT"
        default: return String(type.prefix(2)).uppercased()
        }
    }
}

struct PlaceHeat: Decodable, Hashable {
    let label: String?
    let side: String?
}

struct PlaceType: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int?
}

struct MyPlaces: Decodable {
    let dashboard: Place?
    let favorites: [Place]?
    let recents: [Place]?
    let statewide: Place?
}

struct PlacesTop: Decodable {
    let mine: MyPlaces?
    let types: [PlaceType]?
}

enum PlacesService {
    private static let base = "https://\(AppIdentity.hubHost)/api/places/"

    /// The top of the picker: cached first, then the Hub's.
    static func top() -> AsyncStream<PlacesTop> {
        guard let url = URL(string: base) else { return AsyncStream { $0.finish() } }
        return HubCache.stream(url, family: .member, as: PlacesTop.self)
    }

    static func search(_ query: String) async -> [Place] {
        struct Reply: Decodable { let items: [Place]? }
        var parts = URLComponents(string: base)
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = parts?.url else { return [] }
        return await HubCache.value(url, family: .catalog, as: Reply.self)?.items ?? []
    }

    static func browse(type: String) async -> [Place] {
        struct Reply: Decodable { let items: [Place]? }
        var parts = URLComponents(string: base)
        parts?.queryItems = [URLQueryItem(name: "type", value: type)]
        guard let url = parts?.url else { return [] }
        return await HubCache.value(url, family: .catalog, as: Reply.self)?.items ?? []
    }
}

