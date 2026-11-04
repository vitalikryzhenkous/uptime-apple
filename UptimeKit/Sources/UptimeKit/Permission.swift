import Foundation

/// An open permission request of a session on the board's machine (uptime-board docs/api.md, `permissions[]` in
/// `/api/v1/status`; only with the board's opt-in `remote_approve`). The terminal's dialog stays open meanwhile:
/// whoever answers first wins.
public struct PermissionRequest: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let session: String
    public let tool: String?
    public let what: String?
    /// The command or path as it is (line breaks as ⏎); `KEY=` values and known tokens cut out.
    public let command: String?
    /// The command is on the board's risky list, or a file tool writes outside the project: deny only.
    public let danger: Bool?
    /// Something was cut out, or it is longer than shown: deny only.
    public let partial: Bool?
    public let created: Double?
    public let expires: Double?
}

/// "Allow once" or "deny" — "always allow" stays in the terminal.
public enum PermissionDecision: String, Sendable { case allow, deny }

public enum DecisionResult: Equatable, Sendable {
    case done
    /// The server's reason (`decided`, `terminal_only`, `request`, `off`, …).
    case refused(String)
}

public protocol DecisionSink: Sendable {
    func decide(_ decision: PermissionDecision, request id: String) async throws -> DecisionResult
}

extension APIClient: DecisionSink {
    static let requestIDPattern = #"^[A-Za-z0-9_-]{16,32}$"#

    public func decide(_ decision: PermissionDecision, request id: String) async throws -> DecisionResult {
        guard id.range(of: Self.requestIDPattern, options: .regularExpression) != nil else { return .refused("request") }
        var req = request("api/v1/permissions/\(id)")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["decision": decision.rawValue])
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200: return .done
        case 401: throw APIError.unauthorized
        case 503: throw APIError.notConfigured
        case 400, 403, 404, 409:
            struct Refusal: Decodable { let error: String? }
            let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error
            return .refused(code.flatMap { $0.range(of: #"^[a-z_]{1,24}$"#, options: .regularExpression) != nil ? $0 : nil }
                            ?? "http_\(http.statusCode)")
        default: throw APIError.badStatus(http.statusCode)
        }
    }
}

extension Panel {
    /// The open request behind a card's permission dialog (the newest, if there are several); nil when the card
    /// shows no permission dialog, the request expired, or the board's opt-in is off.
    public static func permission(for s: AgentStream, in requests: [PermissionRequest]?, now: Double) -> PermissionRequest? {
        guard s.stateKind == .waiting, s.asksPermission, let id = s.session else { return nil }
        return (requests ?? [])
            .filter { $0.session == id && ($0.expires ?? .infinity) > now }
            .max { ($0.created ?? 0) < ($1.created ?? 0) }
    }

    /// "Allow once" is offered only for a request that is neither risky nor partly hidden (a missing flag counts as
    /// set: the server decides again and refuses with `terminal_only`).
    public static func canAllow(_ r: PermissionRequest) -> Bool {
        r.danger == false && r.partial == false
    }

    /// Why only "deny" is offered, or nil when "allow once" is too.
    public static func denyOnlyText(_ r: PermissionRequest, _ t: Strings) -> String? {
        if canAllow(r) { return nil }
        if r.partial == true && r.danger != true {
            return t.tr("app.perm.partial", fallback: "Not all of it is shown: allow it only in the terminal")
        }
        return t.tr("app.perm.danger", fallback: "A risky command: allow it only in the terminal")
    }

    /// What the popover shows for a request: the command as the board got it, else the card's line.
    public static func permissionText(_ r: PermissionRequest, s: AgentStream, _ t: Strings) -> String {
        if let c = r.command, !c.isEmpty { return c }
        return askLine(s, t) ?? r.what ?? r.tool ?? ""
    }

    /// A short line for a refusal or a failed answer.
    public static func decisionErrorText(_ code: String, _ s: Strings) -> String {
        let fallback: String = switch code {
        case "decided": "Already answered"
        case "terminal_only": "Allow it only in the terminal"
        case "request": "The request is closed"
        case "off": "Answering from the apps is off on the board"
        case "network": "No connection to the board — nothing sent"
        default: "Couldn't answer (\(code))"
        }
        return s.tr("app.perm.err.\(code)", fallback: fallback)
    }
}
