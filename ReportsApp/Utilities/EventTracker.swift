//
//  EventTracker.swift
//  ReportsApp
//
//  Fire-and-forget usage events to the same /api/track/ endpoint the website
//  uses. Until this existed, the app's only footprint in the engagement
//  dashboard was spark_chats (recorded server-side): 93 connected accounts and
//  the only thing visible about them was whether they chatted. Everything here
//  is best-effort — a tracking failure must never surface in the UI.
//

import Foundation

enum EventTracker {

    /// Event keys shared with the web dashboard. Keep in the site's existing
    /// vocabulary (ENGAGEMENT_CATEGORIES in views.py) so app and web roll up
    /// into the same buckets, plus app_open for app-only sessions.
    enum Event: String {
        case appOpen = "app_open"
        case viewReports = "view_reports"
        case viewMarkets = "view_markets"
    }

    /// De-dup within a session so a TabView re-selecting a tab doesn't count
    /// as a fresh view. Keyed by event + metadata identity.
    private static var firedThisSession = Set<String>()

    static func fire(_ event: Event, metadata: [String: String] = [:], oncePerSession: Bool = false) {
        let sessionKey = event.rawValue + "|" + metadata.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        if oncePerSession {
            guard !firedThisSession.contains(sessionKey) else { return }
            firedThisSession.insert(sessionKey)
        }

        var components = URLComponents(string: "\(ChatManager.serverBaseURL)/api/track/")!
        // Identity rides the query string: the server reads chat_user_id from
        // GET params, and a JSON body isn't parsed into request.POST.
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["event_key": event.rawValue]
        if !metadata.isEmpty { payload["metadata"] = metadata }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request).resume()
    }
}
