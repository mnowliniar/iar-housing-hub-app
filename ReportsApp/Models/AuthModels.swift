//
//  AuthExchangeResponse.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/12/26.
//


import Foundation

struct AuthExchangeResponse: Decodable {
    let ok: Bool
    let accessToken: String
    let tokenType: String
    let expiresAt: String
    let wpUserId: Int
    let chatUserID: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case wpUserId = "wp_user_id"
        case chatUserID = "chat_user_id"
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Date
    let wpUserId: Int
    let chatUserID: String?
    var isExpired: Bool {
        Date() >= expiresAt
    }
}

enum AuthState: Equatable {
    case launching
    case signedOut
    case signingIn
    case signedIn
    case error(String)
}
