import Foundation
import UptimeKit

/// Settings: the server address in UserDefaults (not secret), the token only in the Keychain.
enum Prefs {
    static let baseURLKey = "baseURL"
    static let tokens: any TokenStore = KeychainTokenStore()

    static var baseURL: URL {
        get {
            UserDefaults.standard.string(forKey: baseURLKey).flatMap(validURL) ?? ServerConfig.defaultBaseURL
        }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: baseURLKey) }
    }

    /// `https://host[:port]` only — the token must never go over plain HTTP.
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// For `LiveStore`: a client from the current settings, `nil` without a token.
    @Sendable static func makeSource() -> (any StatusSource)? {
        guard let token = tokens.read(), !token.isEmpty else { return nil }
        return APIClient(baseURL: baseURL, token: token)
    }
}
