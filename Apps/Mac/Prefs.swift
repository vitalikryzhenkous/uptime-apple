import Foundation
import UptimeKit

/// Settings: server address and language in UserDefaults (not secret), the token only in the Keychain.
enum Prefs {
    static let baseURLKey = "baseURL"
    static let langKey = "lang"
    static let tokens: any TokenStore = KeychainTokenStore()

    static var baseURL: URL {
        get {
            UserDefaults.standard.string(forKey: baseURLKey).flatMap(validURL) ?? ServerConfig.defaultBaseURL
        }
        set { UserDefaults.standard.set(newValue.absoluteString, forKey: baseURLKey) }
    }

    /// The user's language; `nil` = the board's default.
    /// What the card's terminal button copies; {folder} and {project} are filled in. Empty = no button.
    static var connectTemplate: String {
        get { UserDefaults.standard.string(forKey: "connect") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "connect") }
    }

    static var lang: String? {
        get { UserDefaults.standard.string(forKey: langKey).flatMap { Strings.isValidCode($0) ? $0 : nil } }
        set { UserDefaults.standard.set(newValue ?? "", forKey: langKey) }
    }

    /// `https://host[:port]` only — the token must never go over plain HTTP.
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// A client from the current settings, `nil` without a token.
    static func makeClient() -> APIClient? {
        guard let token = tokens.read(), !token.isEmpty else { return nil }
        return APIClient(baseURL: baseURL, token: token)
    }

    /// For `LiveStore`.
    @Sendable static func makeSource() -> (any StatusSource)? { makeClient() }
}
