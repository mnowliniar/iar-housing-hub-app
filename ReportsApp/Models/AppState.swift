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
        debugLog("[Prefs] fetch URL:", url.absoluteString)

        let (data, response) = try await URLSession.shared.data(for: .app(url))

        if let http = response as? HTTPURLResponse {
            debugLog("[Prefs] fetch status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Prefs] fetch raw response:", raw)
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
        debugLog("[Prefs] save URL:", url.absoluteString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UserPrefsSaveRequest(prefs: prefs))

        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())

        if let http = response as? HTTPURLResponse {
            debugLog("[Prefs] save status:", http.statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            debugLog("[Prefs] save raw response:", raw)
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
    /// A Spark chat to open, from a universal link.
    @Published var sparkThreadToOpen: String? = nil
    /// A market page to open, from a universal link.
    @Published var marketGeoID: String? = nil
    /// A recipe to run in Spark, from Home's launcher.
    @Published var recipeToRun: SparkRecipe? = nil
    @Published var activeReport: ActiveReport? = nil
    @Published var showDigest: Bool = false

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
            debugLog("[Prefs] load failed:", error)
        }
    }

    func saveUserPrefs() {
        userPrefs.app.selectedGeoID = selectedGeoID
        let prefs = userPrefs

        Task {
            do {
                try await prefsService.savePrefs(prefs)
            } catch {
                debugLog("[Prefs] save failed:", error)
            }
        }
    }

    func handleDeepLink(_ url: URL) {
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            handleHubLink(url)
            return
        }
        guard url.scheme?.lowercased() == "iarhousinghub" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.host == "spark" {
            let query = components?.queryItems?.first(where: { $0.name == "q" })?.value
            sparkPrompt = query
            selectedTab = 2
            return
        }

        if url.host == "digest" {
            showDigest = true
            selectedTab = 1
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

    /// Universal links: a Hub link tapped in Mail, Messages or Safari. The
    /// server's apple-app-site-association decides which paths come here: a
    /// Spark chat, a report, a market. Editors under a chat stay on the web.
    private func handleHubLink(_ url: URL) {
        guard url.host?.lowercased() == AppIdentity.hubHost else { return }
        var parts = url.pathComponents.filter { $0 != "/" }
        // /reports/... mirrors the root routes.
        if parts.first == "reports" { parts.removeFirst() }
        guard let first = parts.first else { return }

        switch first {
        case "chat":
            // /chat/<thread>/
            guard parts.count >= 2 else { return }
            sparkThreadToOpen = parts[1].lowercased()
            selectedTab = 2
        case "market":
            // /market/<geo>/
            guard parts.count >= 2, Int(parts[1]) != nil else { return }
            marketGeoID = parts[1]
            selectedTab = 0
        case "viewreport":
            // /viewreport/<report>/<proptype>/<geo>/[<yyyy>/<m>/<d>/]
            guard parts.count >= 4, let reportID = Int(parts[1]) else { return }
            let geoID = parts[3]
            var date: String?
            if parts.count >= 7, let y = Int(parts[4]), let m = Int(parts[5]), let d = Int(parts[6]) {
                date = String(format: "%04d-%02d-%02d", y, m, d)
            }
            Task { await openReport(reportID: reportID, geoID: geoID, date: date) }
        default:
            return
        }
    }

    /// Shows a report from a link. Without a date in the link, the latest.
    private func openReport(reportID: Int, geoID: String, date: String?) async {
        guard let geo = await APIService.fetchGeo(geoid: geoID) else { return }
        var updateDate = date
        if updateDate == nil {
            updateDate = try? await APIService.fetchLatestReportDate(reportID: reportID, geoID: geoID)
        }
        guard let updateDate, !updateDate.isEmpty else { return }
        activeReport = ActiveReport(report: Report(id: reportID, title: "Report"), geo: geo, updateDate: updateDate)
    }
}
