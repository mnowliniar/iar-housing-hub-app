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
        // Spark: same keys the web's step records map to (save_step_view).
        case sparkCopy = "spark_copy"        // chart image, table, post/email/script card
        case sparkExport = "spark_export"    // chart graphic or table file shared out
        // Workflow and favorites, as the web fires them.
        case exportChart = "export_chart"    // report sent to the printer
        case downloadInsightChart = "download_insight_chart"  // insight card shared
        case favoriteMarkets = "favorite_markets"
        case favoriteReports = "favorite_reports"
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

        // Identity rides the query string: the server reads chat_user_id from
        // GET params, and a JSON body isn't parsed into request.POST.
        guard let base = URL(string: "\(ChatManager.serverBaseURL)/api/track/") else { return }
        let url = base.appendingChatUserID()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // client=ios separates app actions from web ones in the dashboard,
        // since most keys are shared.
        var meta = metadata
        meta["client"] = "ios"
        let payload: [String: Any] = ["event_key": event.rawValue, "metadata": meta]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request).resume()
    }

    /// A Spark action on the open conversation. Adds the thread ID the web
    /// sends with the same events.
    static func fireSpark(_ event: Event, kind: String, target: String? = nil) {
        var metadata = ["kind": kind]
        if let thread = UserDefaults.standard.string(forKey: "currentChatThreadID"), !thread.isEmpty {
            metadata["thread_id"] = thread
        }
        // The server skips a repeat of the same key and metadata within 30
        // minutes, so a target keeps two different charts from merging.
        if let target, !target.isEmpty { metadata["target"] = String(target.prefix(80)) }
        fire(event, metadata: metadata)
    }
}

extension URL {
    /// Adds the member's chat_user_id query item. Server endpoints that log
    /// events (share links, one-sheet PDFs) can only attribute an app request
    /// that carries it.
    func appendingChatUserID() -> URL {
        guard let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == "chat_user_id" }) else { return self }
        items.append(URLQueryItem(name: "chat_user_id", value: chatUserID))
        components.queryItems = items
        return components.url ?? self
    }
}
