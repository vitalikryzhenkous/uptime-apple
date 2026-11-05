import Foundation

/// Pairing with the board (uptime-board docs/api.md, "Pairing"): a one-time code from `tools/pair.py` becomes this
/// app's own revocable token, so the main UPTIME_API_TOKEN is never copied out of the board's .env.
public enum Pairing {
    /// `uptime://pair?code=123456&url=https://…` — the link `tools/pair.py` prints (⌘-click it in Terminal).
    public struct Link: Equatable, Sendable {
        public let code: String
        public let baseURL: URL?
    }

    public enum Outcome: Equatable, Sendable {
        case paired(token: String)
        /// `code` (wrong, used or expired), `rate` (too many attempts: wait a minute), `old_board` (no pairing yet).
        case refused(String)
    }

    /// Six digits; the spaces and dashes people type are dropped.
    public static func code(_ text: String) -> String? {
        let digits = text.filter { !$0.isWhitespace && $0 != "-" }
        return digits.count == 6 && digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? digits : nil
    }

    public static func link(_ url: URL) -> Link? {
        guard url.scheme?.lowercased() == "uptime", url.host?.lowercased() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value.flatMap(code(_:)) else { return nil }
        return Link(code: code, baseURL: items.first(where: { $0.name == "url" })?.value.flatMap(httpsBase(_:)))
    }

    /// `https://host[:port]` only — the token must never go over plain HTTP; path, query and user info are dropped.
    public static func httpsBase(_ text: String) -> URL? {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty else { return nil }
        c.path = ""
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        return c.url
    }

    /// What prints a code on the board's machine, for the wizard's Copy button.
    public static func command(baseURL: URL) -> String {
        "ssh m920q '~/apps/uptime-board/tools/pair.py --url \(baseURL.absoluteString)'"
    }

    /// `POST /api/v1/pair/claim` — no token: the code is the proof. The token comes back once; keep it in the Keychain.
    public static func claim(code: String, name: String, baseURL: URL,
                             session: URLSession = .shared) async throws -> Outcome {
        var r = URLRequest(url: baseURL.appending(path: "api/v1/pair/claim"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        r.httpBody = try JSONEncoder().encode(["code": code, "name": name])
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200:
            struct Answer: Decodable { let token: String? }
            guard let token = (try? JSONDecoder().decode(Answer.self, from: data))?.token, !token.isEmpty else {
                throw APIError.invalidResponse
            }
            return .paired(token: token)
        case 403: return .refused("code")
        case 429: return .refused("rate")
        case 404, 405: return .refused("old_board")
        default: throw APIError.badStatus(http.statusCode)
        }
    }
}
