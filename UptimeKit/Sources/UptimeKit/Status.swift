import Foundation

// API v1 models — the contract is uptime-board/docs/api.md (`GET /api/v1/status`, SSE `status` event).
// Rules: explicit CodingKeys (no snake-case strategy: it would also rewrite dictionary keys such as git folders
// and `vars`); everything the server may leave out is optional; times are epoch seconds as Double;
// enum-like fields stay String with a typed accessor, so an unknown value never breaks decoding.

public struct Status: Decodable, Sendable {
    public let api: Int
    public let persona: Persona?
    public let nikolai: [CatLine]?
    public let claude: Claude?
    public let git: [String: GitInfo]?
    public let health: [Health]?
    public let machine: Machine?
    public let weather: Weather?
    public let notifications: [AppNotification]?
    public let serverTime: Double?
    public let build: String?
    /// `false` with `error` when the Notion snapshot failed; the live parts are still valid.
    public let ok: Bool?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case api, persona, nikolai, claude, git, health, machine, weather, notifications, build, ok, error
        case serverTime = "server_time"
    }

    /// The cat's main line (carries mood, look and pet).
    public var cat: CatLine? { nikolai?.first }
    public var streams: [AgentStream] { claude?.streams ?? [] }

    /// Git info of a session's repo. The server keys `git` by the repo's folder name in ~/apps ("babyloop"), while a
    /// session's `folder` is relative to home ("apps/babyloop") — the board looks it up by `project`; so do we.
    public func gitInfo(for s: AgentStream) -> GitInfo? {
        guard let git else { return nil }
        let last = (s.folder ?? "").split(separator: "/").last.map(String.init)
        return git[s.project] ?? last.flatMap { git[$0] } ?? s.folder.flatMap { git[$0] }
    }
}

public struct Persona: Decodable, Sendable, Equatable {
    public let name: String
}

// MARK: - Claude sessions

public struct Claude: Decodable, Sendable {
    public let working: Int?
    public let waiting: Int?
    public let idle: Int?
    public let open: Int?
    public let streams: [AgentStream]?
    public let limits: Limits?
}

public enum StreamState: String, Sendable {
    case working, waiting, open, idle, unknown
}

/// One live session folder (a card on the board).
public struct AgentStream: Decodable, Sendable, Identifiable {
    public let project: String
    public let folder: String?
    public let sessionId: String?
    public let state: String
    /// `permission` when the agent waits for a permission.
    public let ask: String?
    public let since: Double?
    public let started: Double?
    public let doing: Action?
    public let plan: Plan?
    public let recent: [Action]?
    public let tasks: [TaskItem]?
    public let count: Int?
    public let remote: Bool?
    public let host: String?
    public let model: String?
    public let ctx: ContextUse?
    public let compact: Compaction?
    public let subs: [Subagent]?
    /// While it waits for a permission: the tool and its safe short form (`Bash` · `git push`).
    public let askTool: Action?
    /// Opt-in on the board (`share_text`): the start of the command the permission is for.
    public let askText: String?
    /// Opt-in on the board: the end of the agent's last reply (usually its question).
    public let lastMsg: String?
    /// Remote Control session id, when the session has one.
    public let rc: String?
    /// Opt-in on the board: while it asks a question, the option labels (picked in the terminal).
    public let askOptions: [String]?
    /// Tool calls in the current turn (newer boards).
    public let turnActions: Int?
    /// When the current turn began (the last prompt; newer boards).
    public let turnStarted: Double?
    /// The hook's short session id: where `POST …/input` goes.
    public let session: String?
    /// The tmux pane the session runs in on the board's machine (v1 only); set = the card can reply.
    public let pane: String?

    enum CodingKeys: String, CodingKey {
        case project, folder, state, ask, since, started, doing, plan, recent, tasks, count, remote, host, model, ctx,
             compact, subs, rc, session, pane
        case sessionId = "id"
        case askTool = "ask_tool"
        case askText = "ask_text"
        case askOptions = "ask_options"
        case lastMsg = "last_msg"
        case turnActions = "turn_actions"
        case turnStarted = "turn_started"
    }

    public var id: String { folder ?? project }
    public var stateKind: StreamState { StreamState(rawValue: state) ?? .unknown }
    public var asksPermission: Bool { ask == "permission" }
    /// Where "working · N min" counts from: the turn's start; older boards only send the last event's time
    /// (which restarts the count after every tool call), then the session's start.
    public var turnStart: Double? { turnStarted ?? since ?? started }
    /// The agent asks you to pick an answer (AskUserQuestion) — a dialog too, not a permission.
    public var asksQuestion: Bool { ask == "question" }
    /// A dialog is open in the terminal: typing there would pick an option.
    public var inDialog: Bool { asksPermission || asksQuestion }

    /// The session on claude.ai (Remote Control docs: the session URL is claude.ai/code/<id>).
    public var claudeURL: URL? {
        guard let rc, rc.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://claude.ai/code/\(rc)")
    }
}

public struct Action: Decodable, Sendable, Hashable {
    public let tool: String?
    public let what: String?
    public let ts: Double?
}

public struct Plan: Decodable, Sendable {
    public let done: Int?
    public let total: Int?
    public let now: String?
}

public struct TaskItem: Decodable, Sendable {
    public let subject: String?
    public let status: String?
}

public struct ContextUse: Decodable, Sendable {
    /// % of the context window used.
    public let pct: Double
    public let size: Int?
    public let tokens: Int?
    /// % where the window fills (autoCompactWindow, else 100).
    public let limit: Double?
    /// ≈turns until full; `nil` until the server knows.
    public let turnsLeft: Int?

    enum CodingKeys: String, CodingKey {
        case pct, size, tokens, limit
        case turnsLeft = "turns_left"
    }
}

public struct Compaction: Decodable, Sendable {
    public let ts: Double
    public let trigger: String?
    public let done: Bool?
}

public struct Subagent: Decodable, Sendable, Identifiable {
    public let id: String
    public let type: String?
    public let state: String
    public let started: Double?
    public let ended: Double?
    public let doing: Action?
    /// The Agent call's short description.
    public let what: String?

    public var isWorking: Bool { state == "working" }
}

public struct Limits: Decodable, Sendable {
    public let ts: Double?
    /// 5-hour window; `nil` when its reset has passed.
    public let h5: LimitWindow?
    /// Weekly window.
    public let d7: LimitWindow?
}

public struct LimitWindow: Decodable, Sendable {
    public let pct: Double
    public let reset: Double?
}

// MARK: - Git, health, machine, weather

public enum CheckState: String, Sendable {
    case ok, fail, run
}

public struct GitInfo: Decodable, Sendable {
    public let branch: String?
    /// Number of changed files.
    public let dirty: Int?
    public let ahead: Int?
    public let ci: String?
    public let ciUrl: String?
    public let prs: [PullRequest]?

    enum CodingKeys: String, CodingKey {
        case branch, dirty, ahead, ci, prs
        case ciUrl = "ci_url"
    }

    public var ciState: CheckState? { ci.flatMap(CheckState.init(rawValue:)) }
    public var ciLink: URL? { GitHubLink.url(ciUrl) }
}

public struct PullRequest: Decodable, Sendable, Identifiable {
    public let n: Int
    public let title: String?
    public let branch: String?
    public let draft: Bool?
    public let checks: String?
    public let url: String?

    public var id: Int { n }
    public var checksState: CheckState? { checks.flatMap(CheckState.init(rawValue:)) }
    public var link: URL? { GitHubLink.url(url) }
}

/// Only plain github.com PR / workflow-run links are opened (the server checks too; the app does not trust it blindly).
public enum GitHubLink {
    public static func url(_ text: String?) -> URL? {
        guard let text,
              text.range(of: #"^https://github\.com/[\w.-]+/[\w.-]+/(pull|actions/runs)/\d+$"#,
                         options: .regularExpression) != nil else { return nil }
        return URL(string: text)
    }
}

public struct Health: Decodable, Sendable {
    /// `docker · https · systemd`
    public let kind: String
    public let name: String
    public let ok: Bool
    public let detail: String?
    public let detailKey: String?
    public let detailVars: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case kind, name, ok, detail
        case detailKey = "detail_key"
        case detailVars = "detail_vars"
    }
}

public struct Machine: Decodable, Sendable {
    public let cpu: Double?
    public let ram: Double?
    public let load: Double?
    public let cores: Int?
    /// `nil` where no sensor exists.
    public let temp: Double?
    public let disk: Double?
    public let docker: Int?
}

public struct Weather: Decodable, Sendable {
    public let temp: Double?
    public let feels: Double?
    public let wind: Double?
    public let key: String?
    public let text: String?
    public let group: String?
    public let day: Bool?
    public let min: Double?
    public let max: Double?
    public let rain: Double?
}

// MARK: - The cat

public struct CatLine: Decodable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let key: String?
    public let vars: [String: JSONValue]?
    /// The line in the server's default language (fallback when the key is missing locally).
    public let text: String?
    public let project: String?
    public let buttons: [CatButton]?
    // only on the first line:
    public let mood: String?
    public let scene: String?
    public let cold: Bool?
    public let look: Look?
    public let pet: Pet?
}

public struct CatButton: Decodable, Sendable, Identifiable {
    public let id: String
    public let key: String?
    public let label: String?
    /// `true` — answering writes a Session Log entry.
    public let log: Bool?
}

/// Draw `poses[pose]` from /sprites.json, then each overlay on top.
public struct Look: Decodable, Sendable {
    public let pose: String
    public let overlays: [String]?
    /// `rain · snow · storm · fog · hot · night · dark · clear · cloudy · none`
    public let scene: String?
    public let mark: String?
    public let anim: String?
    public let glow: Bool?
}

/// Tamagotchi needs, 0–100.
public struct Pet: Decodable, Sendable {
    public let food: Int
    public let fun: Int
    public let love: Int
}

// MARK: - Notifications

public enum NotificationKind: String, Sendable {
    case done, permission, waiting, down, limit, context, unknown
}

/// One of the last 50 notifications. Ids are stable: show each id once, never by position.
public struct AppNotification: Decodable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let titleKey: String?
    public let bodyKey: String?
    public let vars: [String: JSONValue]?
    public let title: String?
    public let body: String?
    public let project: String?
    public let ts: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, vars, title, body, project, ts
        case titleKey = "title_key"
        case bodyKey = "body_key"
    }

    public var kindValue: NotificationKind { NotificationKind(rawValue: kind) ?? .unknown }
}

// MARK: - Decoding

public enum UptimeJSON {
    /// The API version this client understands; a bigger `api` means a breaking change.
    public static let supportedAPI = 1

    public static func status(from data: Data) throws -> Status {
        try JSONDecoder().decode(Status.self, from: data)
    }
}
