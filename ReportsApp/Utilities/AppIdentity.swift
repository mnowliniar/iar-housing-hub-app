import Foundation

/// The signed-in member's credentials for Hub requests. AuthManager sets
/// `authorization` on sign-in, restore and sign-out; request code anywhere,
/// including the files shared with the watch, reads it.
///
/// The server resolves the Bearer token to the member and prefers it over
/// the chat_user_id query param, which anyone could type. The param still
/// rides along so older servers and pre-token sessions keep working.
enum AppIdentity {
    static let hubHost = "data.indianarealtors.com"

    private static let lock = NSLock()
    private static var storedAuthorization: String?

    /// "Bearer <token>", or nil when signed out.
    static var authorization: String? {
        get { lock.lock(); defer { lock.unlock() }; return storedAuthorization }
        set { lock.lock(); storedAuthorization = newValue; lock.unlock() }
    }
}

extension URLRequest {
    /// A request for `url` carrying the member's token when it goes to the Hub.
    static func app(_ url: URL) -> URLRequest {
        URLRequest(url: url).withAppIdentity()
    }

    /// This request plus the Authorization header. Only the Hub's own host
    /// gets the token, so a request to any other site never carries it.
    func withAppIdentity() -> URLRequest {
        guard url?.host == AppIdentity.hubHost,
              value(forHTTPHeaderField: "Authorization") == nil,
              let auth = AppIdentity.authorization else { return self }
        var copy = self
        copy.setValue(auth, forHTTPHeaderField: "Authorization")
        return copy
    }
}
