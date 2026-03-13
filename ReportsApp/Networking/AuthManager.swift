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
                state = .signedOut
                return
            }

            let decoded = try JSONDecoder.authDecoder.decode(AuthSession.self, from: data)

            if decoded.isExpired {
                clearSession()
                state = .signedOut
                return
            }

            self.session = decoded
            self.state = .signedIn
        } catch {
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

            let expiresAt = ISO8601DateFormatter().date(from: decoded.expiresAt) ?? Date().addingTimeInterval(60 * 60)

            let newSession = AuthSession(
                accessToken: decoded.accessToken,
                tokenType: decoded.tokenType,
                expiresAt: expiresAt,
                wpUserId: decoded.wpUserId
            )

            try persistSession(newSession)
            self.session = newSession
            self.state = .signedIn
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
        let data = try JSONEncoder().encode(session)
        try KeychainHelper.save(data, account: sessionAccount)
    }

    private func clearSession() {
        KeychainHelper.delete(account: sessionAccount)
        session = nil
    }
}

private extension JSONDecoder {
    static var authDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
