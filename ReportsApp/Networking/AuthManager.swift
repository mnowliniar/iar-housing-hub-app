//
//  AuthManager.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/12/26.
//


import Foundation
import SwiftUI
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    @Published var state: AuthState = .launching
    @Published var session: AuthSession?

    private let sessionAccount = "auth_session"
    var onSignedIn: (() -> Void)?

    private let appExchangeURL = URL(string: "https://data.indianarealtors.com/app_auth_exchange")!

    // This should be your WP/Django entry point that eventually lands on app_connect
    let loginStartURL = URL(string:
        "https://indianarealtors.com/wp-login.php?redirect_to=https%3A%2F%2Findianarealtors.com%2Fdataredirect.php%3Fredirect%3Dhttps%3A%2F%2Fdata.indianarealtors.com%2Fapp_connect"
    )!

    init() {
        restoreSession()
    }

    func restoreSession() {
        do {
            guard let data = try KeychainHelper.load(account: sessionAccount) else {
                print("[Auth] restoreSession: no keychain data")
                state = .signedOut
                return
            }

            print("[Auth] restoreSession: loaded bytes:", data.count)

            let decoded = try JSONDecoder.authDecoder.decode(AuthSession.self, from: data)
            print("[Auth] restoreSession decoded expiresAt:", decoded.expiresAt)
            print("[Auth] restoreSession decoded isExpired:", decoded.isExpired)
            print("[Auth] restoreSession decoded chatUserID:", decoded.chatUserID ?? "nil")

            if decoded.isExpired {
                print("[Auth] restoreSession: session expired")
                clearSession()
                state = .signedOut
                return
            }

            self.session = decoded
            if let chatUserID = decoded.chatUserID {
                UserDefaults.standard.set(chatUserID, forKey: "chat_user_id")
            }
            self.state = .signedIn
            onSignedIn?()
        } catch {
            print("[Auth] restoreSession failed:", error)
            clearSession()
            state = .signedOut
        }
    }

    func startLogin() {
        state = .signingIn
        UIApplication.shared.open(loginStartURL)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "iarhousinghub" else { return }
        guard url.host == "auth" else { return }
        guard url.path == "/callback" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            state = .error("Missing auth code")
            return
        }

        let chatUserID = components.queryItems?.first(where: { $0.name == "chat_user_id" })?.value

        if let chatUserID {
            UserDefaults.standard.set(chatUserID, forKey: "chat_user_id")
            print("[Auth] chat_user_id received:", chatUserID)
        } else {
            print("[Auth] chat_user_id missing in callback")
        }

        Task {
            await exchangeCode(code)
        }
    }

    func exchangeCode(_ code: String) async {
        state = .signingIn

        var request = URLRequest(url: appExchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["code": code]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                state = .error("No server response")
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Exchange failed"
                state = .error(message)
                return
            }

            let decoded = try JSONDecoder().decode(AuthExchangeResponse.self, from: data)

            guard let expiresAt = parseServerDate(decoded.expiresAt) else {
                print("[Auth] exchangeCode invalid expiresAt:", decoded.expiresAt)
                state = .error("Invalid expiration date from server")
                return
            }

            let newSession = AuthSession(
                accessToken: decoded.accessToken,
                tokenType: decoded.tokenType,
                expiresAt: expiresAt,
                wpUserId: decoded.wpUserId,
                chatUserID: decoded.chatUserID ?? UserDefaults.standard.string(forKey: "chat_user_id")
            )

            try persistSession(newSession)
            self.session = newSession
            self.state = .signedIn
            onSignedIn?()
        } catch {
            state = .error("Sign-in failed")
        }
    }

    func logout() {
        clearSession()
        state = .signedOut
    }

    func authHeader() -> String? {
        guard let session, !session.isExpired else { return nil }
        return "\(session.tokenType) \(session.accessToken)"
    }

    private func persistSession(_ session: AuthSession) throws {
        let data = try JSONEncoder.authEncoder.encode(session)
        print("[Auth] persistSession expiresAt:", session.expiresAt)
        print("[Auth] persistSession chatUserID:", session.chatUserID ?? "nil")
        print("[Auth] persistSession bytes:", data.count)
        try KeychainHelper.save(data, account: sessionAccount)
    }

    private func clearSession() {
        KeychainHelper.delete(account: sessionAccount)
        UserDefaults.standard.removeObject(forKey: "chat_user_id")
        session = nil
    }
}

private extension JSONDecoder {
    static var authDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var authEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private func parseServerDate(_ value: String) -> Date? {
    let isoWithFractional = ISO8601DateFormatter()
    isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoWithFractional.date(from: value) {
        return date
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) {
        return date
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.date(from: value)
}
