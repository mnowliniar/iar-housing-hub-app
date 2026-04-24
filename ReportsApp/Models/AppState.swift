//
//  AppState.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//

import Foundation

struct UserPrefsEnvelope: Codable {
    let ok: Bool
    let userID: String
    let prefs: UserPrefs

    enum CodingKeys: String, CodingKey {
        case ok
        case userID = "user_id"
        case prefs
    }
}

struct UserPrefsSaveRequest: Codable {
    let prefs: UserPrefs
}

struct UserPrefs: Codable {
    var app: AppPrefs = .init()
    var web: [String: String]? = nil
}

struct AppPrefs: Codable {
    var favoriteMarketIDs: [Int] = []
    var favoriteReportIDs: [Int] = []
    var selectedGeoID: String? = nil
    var dashboardVizIDs: [Int] = [9, 3, 7]
    var dashboardGeoID: String? = "18"
}

struct UserPrefsService {
    private let baseURL = "https://data.indianarealtors.com"

    func fetchPrefs() async throws -> UserPrefs {
        guard let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty else {
            return UserPrefs()
        }

        var components = URLComponents(string: "\(baseURL)/app/user_prefs/")!
        components.queryItems = [
            URLQueryItem(name: "chat_user_id", value: chatUserID)
        ]

        let url = components.url!
        print("[Prefs] fetch URL:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse {
            print("[Prefs] fetch status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[Prefs] fetch raw response:", raw)
        }

        return try JSONDecoder().decode(UserPrefsEnvelope.self, from: data).prefs
    }

    func savePrefs(_ prefs: UserPrefs) async throws {
        guard let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty else {
            return
        }

        var components = URLComponents(string: "\(baseURL)/app/user_prefs/save/")!
        components.queryItems = [
            URLQueryItem(name: "chat_user_id", value: chatUserID)
        ]

        let url = components.url!
        print("[Prefs] save URL:", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UserPrefsSaveRequest(prefs: prefs))

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            print("[Prefs] save status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[Prefs] save raw response:", raw)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }
}

struct ActiveReport: Identifiable {
    var id: String { "\(report.id)-\(geo.geoid)-\(updateDate)" }
    let report: Report
    let geo: Geo
    let updateDate: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var userPrefs = UserPrefs()
    @Published var selectedGeoID: String = "18" // default market (Indiana)
    @Published var selectedTab: Int = 0
    @Published var sparkPrompt: String? = nil
    @Published var insightGeoID: String? = nil
    @Published var activeReport: ActiveReport? = nil

    private let prefsService = UserPrefsService()

    func loadUserPrefs() async {
        do {
            let prefs = try await prefsService.fetchPrefs()
            userPrefs = prefs

            if prefs.app.dashboardVizIDs.isEmpty {
                userPrefs.app.dashboardVizIDs = [9, 3, 7]
            }
            
            if prefs.app.dashboardGeoID == nil || prefs.app.dashboardGeoID == "" {
                userPrefs.app.dashboardGeoID = "18"
            }

            if let selectedGeoID = prefs.app.selectedGeoID, !selectedGeoID.isEmpty {
                self.selectedGeoID = selectedGeoID
            }
        } catch {
            print("[Prefs] load failed:", error)
        }
    }

    func saveUserPrefs() {
        userPrefs.app.selectedGeoID = selectedGeoID
        let prefs = userPrefs

        Task {
            do {
                try await prefsService.savePrefs(prefs)
            } catch {
                print("[Prefs] save failed:", error)
            }
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "iarhousinghub" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.host == "spark" {
            let query = components?.queryItems?.first(where: { $0.name == "q" })?.value
            sparkPrompt = query
            selectedTab = 2
            return
        }

        if url.host == "market" {
            let pathComponents = url.pathComponents.filter { $0 != "/" }

            if let geoID = pathComponents.first {
                insightGeoID = geoID
            }

            if pathComponents.count > 1, pathComponents[1].lowercased() == "insights" {
                selectedTab = 0
            }
        }
    }
}
