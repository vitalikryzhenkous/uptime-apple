import Foundation

/// What the panel can type into a waiting session (uptime-board docs/api.md, `POST /api/v1/sessions/<id>/input`):
/// a one-line reply or the fixed `/compact`. The server checks everything again; these checks only spare a round trip.
public enum AgentInput: Equatable, Sendable {
    case reply(String)
    case compact

    public static let maxLength = 500

    /// Why a draft can't be sent yet (`nil` = it can): the same rules as the server.
    public enum Problem: String, Equatable, Sendable { case empty, tooLong = "text", command }

    public static func problem(_ draft: String) -> Problem? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if text.count > maxLength || text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            return .tooLong
        }
        if let first = text.first, "/!#".contains(first) { return .command }
        return nil
    }

    var json: [String: String] {
        switch self {
        case .reply(let text): return ["kind": "reply", "text": text.trimmingCharacters(in: .whitespacesAndNewlines)]
        case .compact: return ["kind": "compact"]
        }
    }
}

public enum InputResult: Equatable, Sendable {
    case sent
    /// The server's reason (`not_waiting`, `no_tmux`, `too_fast`, …).
    case refused(String)
}

public protocol InputSink: Sendable {
    func send(_ input: AgentInput, to sessionID: String) async throws -> InputResult
}

extension APIClient: InputSink {
    static let sessionIDPattern = #"^[A-Za-z0-9-]{1,12}$"#

    public func send(_ input: AgentInput, to sessionID: String) async throws -> InputResult {
        guard sessionID.range(of: Self.sessionIDPattern, options: .regularExpression) != nil else { return .refused("session") }
        let req: URLRequest = {
            var r = request("api/v1/sessions/\(sessionID)/input")
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONEncoder().encode(input.json)
            return r
        }()
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200: return .sent
        case 401: throw APIError.unauthorized
        case 503: throw APIError.notConfigured
        case 400, 404, 409, 429:
            struct Refusal: Decodable { let error: String? }
            let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error
            return .refused(code.flatMap { $0.range(of: #"^[a-z_]{1,24}$"#, options: .regularExpression) != nil ? $0 : nil }
                            ?? "http_\(http.statusCode)")
        default: throw APIError.badStatus(http.statusCode)
        }
    }
}

extension Panel {
    /// The card offers a reply: the agent waits for you after its turn (no permission or question dialog) in tmux on the
    /// board's machine.
    public static func canReply(_ s: AgentStream) -> Bool {
        guard s.stateKind == .waiting, !s.inDialog, s.remote != true,
              let pane = s.pane, pane.range(of: #"^%\d{1,6}$"#, options: .regularExpression) != nil,
              let id = s.session, id.range(of: APIClient.sessionIDPattern, options: .regularExpression) != nil
        else { return false }
        return true
    }

    /// The /compact button: a reply is possible and the context is at least 70 % full.
    public static func offersCompact(_ s: AgentStream) -> Bool {
        canReply(s) && (s.ctx.map { ctxLevel($0.pct) != .ok } ?? false)
    }

    /// A short line for a refusal or a failed send.
    public static func inputErrorText(_ code: String, _ s: Strings) -> String {
        let fallback: String = switch code {
        case "not_waiting": "It isn't waiting for you any more"
        case "no_tmux", "no_agent": "That session isn't reachable in tmux"
        case "pane_busy": "The terminal is in copy mode"
        case "too_fast": "Just sent — wait a moment"
        case "command": "Commands can't be sent (only /compact)"
        case "text": "One line, up to 500 characters"
        default: "Couldn't send (\(code))"
        }
        return s.tr("app.reply.err.\(code)", fallback: fallback)
    }
}
