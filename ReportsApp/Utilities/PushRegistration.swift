//
//  PushRegistration.swift
//  ReportsApp
//
//  The Thursday tap needs the phone's APNs token on the Hub. Once
//  notifications are allowed, the app asks iOS for the token and sends it
//  with the member's sign-in; sign-out takes it back. The watch needs
//  nothing of its own: iOS mirrors the notification to the wrist.
//

import UIKit
import UserNotifications

enum PushRegistration {
    private static let tokenKey = "apns_token"

    /// Asks iOS for a token when notifications are already allowed. Safe to
    /// call at every launch and sign-in; iOS answers through the delegate.
    static func registerIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            default:
                break
            }
        }
    }

    /// The delegate hands the token here.
    static func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await send(token) }
    }

    /// A request that removes this phone's token, built now so it still
    /// carries the sign-in that is about to be cleared.
    static func unregisterRequest() -> URLRequest? {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let url = URL(string: "\(ChatManager.serverBaseURL)/app/push/unregister/") else { return nil }
        var request = URLRequest.app(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        return request
    }

    private static func send(_ token: String) async {
        guard AppIdentity.authorization != nil,
              let url = URL(string: "\(ChatManager.serverBaseURL)/app/push/register/") else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var request = URLRequest.app(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "token": token, "platform": "ios", "environment": environment, "app_version": version,
        ])
        _ = try? await URLSession.shared.data(for: request)
    }
}
