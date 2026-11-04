import Foundation

/// How alarming a value is; the UI maps it to the theme's green / yellow / red / grey.
public enum Level: Sendable, Equatable {
    case ok, warn, bad, muted
}

/// The panel's rules, kept out of the views so CI tests them. Thresholds are the board's (web/board.js).
public enum Panel {
    // MARK: thresholds

    /// 5-hour limit: red from 95 %, yellow from 80 %.
    public static func h5Level(_ pct: Double) -> Level { pct >= 95 ? .bad : pct >= 80 ? .warn : .ok }

    /// Weekly limit: red from 95 %, yellow from 70 %, otherwise quiet.
    public static func weekLevel(_ pct: Double) -> Level { pct >= 95 ? .bad : pct >= 70 ? .warn : .muted }

    /// The week gets its own bar only from 70 % (design note: "недельный появляется крупно только после 70 %").
    public static func weekIsBig(_ pct: Double) -> Bool { pct >= 70 }

    /// Context use: red from 85 %, yellow from 70 %.
    public static func ctxLevel(_ pct: Double) -> Level { pct >= 85 ? .bad : pct >= 70 ? .warn : .ok }

    // MARK: sessions

    public static func dot(_ s: AgentStream) -> Level {
        switch s.stateKind {
        case .waiting: return s.asksPermission ? .bad : .warn
        case .working: return .ok
        default: return .muted
        }
    }

    /// How often the card's state strip pulses: quickly when the session needs you, calmly while it works,
    /// not at all when idle or open.
    public static func pulsePeriod(_ s: AgentStream) -> Double? {
        switch s.stateKind {
        case .waiting: return 1.4
        case .working: return 2.8
        default: return nil
        }
    }

    private static func rank(_ s: AgentStream) -> Int {
        switch s.stateKind {
        case .waiting: return s.asksPermission ? 0 : 1
        case .working: return 2
        case .idle: return 3
        case .open: return 4
        case .unknown: return 5
        }
    }

    /// Who needs you first: permission asks, then waiting (longest wait first), working, idle, open.
    public static func sorted(_ streams: [AgentStream]) -> [AgentStream] {
        streams.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            if ra <= 1, let sa = a.since, let sb = b.since, sa != sb { return sa < sb }
            return a.project.localizedStandardCompare(b.project) == .orderedAscending
        }
    }

    /// Sessions waiting for you (the menu-bar badge).
    public static func waitingCount(_ streams: [AgentStream]) -> Int {
        streams.filter { $0.stateKind == .waiting }.count
    }

    /// "uptime-board" or "uptime-board ×2" when several sessions share the folder.
    public static func title(_ s: AgentStream) -> String {
        if let n = s.count, n > 1 { return "\(s.project) ×\(n)" }
        return s.project
    }

    /// The row's second line: state · time, or what matters most while working.
    public static func stateLine(_ s: AgentStream, now: Double, _ t: Strings) -> String {
        func since(_ start: Double?) -> String {
            guard let start else { return "" }
            return " · " + duration(now - start, t)
        }
        switch s.stateKind {
        case .waiting where s.asksPermission:
            return t.tr("app.state.permission", fallback: "waits for permission") + since(s.since)
        case .waiting:
            return t.tr("app.state.waiting", fallback: "waiting for you") + since(s.since)
        case .working:
            var line = t.tr("app.state.working", fallback: "working")
            let running = (s.subs ?? []).filter(\.isWorking).count
            if let c = s.ctx, ctxLevel(c.pct) != .ok, let left = c.turnsLeft {
                line += " · " + t.tp("ctx.turns", count: left, fallback: "≈{n} turns until full")
            } else if running > 0 {
                line += " · " + t.tp("app.subs", count: running, fallback: "{n} subagents")
            } else {
                line += since(s.since ?? s.started) // this turn, not the whole session
            }
            return line
        case .idle:
            return t.tr("app.state.idle", fallback: "idle") + since(s.since)
        case .open, .unknown:
            return t.tr("app.state.open", fallback: "open")
        }
    }

    // MARK: limit resets

    /// claude.ai Settings → Usage, where a granted limit reset is applied (support article "What is a limit reset";
    /// the exact URL is not documented there — this is the settings page's path).
    public static let usageSettingsURL = URL(string: "https://claude.ai/settings/usage")!

    /// Point to the resets once either window is at 80 % or more (where the board's 5 h bar turns yellow).
    public static func suggestsResets(_ l: Limits) -> Bool {
        max(l.h5?.pct ?? 0, l.d7?.pct ?? 0) >= 80
    }

    // MARK: card

    /// What the session waits for: "asks for Bash · git push --force" (the command only with the board's opt-in),
    /// or the end of the agent's last reply (opt-in). `nil` when there is nothing to say.
    public static func askLine(_ s: AgentStream, _ t: Strings) -> String? {
        guard s.stateKind == .waiting || s.stateKind == .idle else { return nil }
        if s.asksPermission {
            var parts: [String] = []
            if let tool = s.askTool?.tool, !tool.isEmpty {
                parts.append(t.tr("app.ask.permission", ["tool": .string(tool)], fallback: "asks for \(tool)"))
            }
            if let text = s.askText, !text.isEmpty {
                parts.append(text)
            } else if let w = s.askTool?.what, !w.isEmpty {
                parts.append(w)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if let m = s.lastMsg, !m.isEmpty { return m }
        return nil
    }

    public struct Progress: Equatable, Sendable {
        public let done: Int
        public let total: Int
        public let step: String?
        public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }

    /// The agent's own plan (TodoWrite / Task tools): steps done of total and the current one.
    public static func planProgress(_ s: AgentStream) -> Progress? {
        guard let p = s.plan, let total = p.total, total > 0 else { return nil }
        let step = (p.now ?? "").isEmpty ? nil : p.now
        return Progress(done: min(p.done ?? 0, total), total: total, step: step)
    }

    /// Without a plan, the honest measure of a working turn: how long, and how many tool calls (newer boards).
    public static func turnLine(_ s: AgentStream, now: Double, _ t: Strings) -> String? {
        guard s.stateKind == .working, let start = s.since ?? s.started else { return nil }
        var line = duration(now - start, t)
        if let n = s.turnActions, n > 0 {
            line += " · " + t.tp("app.actions", count: n, fallback: "{n} actions")
        }
        return line
    }

    /// The "copy connect command" text from the user's template: {folder} (relative to home) and {project}.
    /// Only plain path characters are substituted, so a strange folder name cannot inject shell syntax.
    public static func connectCommand(_ template: String, _ s: AgentStream) -> String? {
        let tpl = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tpl.isEmpty else { return nil }
        let safe = #"^[A-Za-z0-9_./~-]{1,120}$"#
        let folder = s.folder ?? s.project
        guard folder.range(of: safe, options: .regularExpression) != nil,
              s.project.range(of: safe, options: .regularExpression) != nil else { return nil }
        return tpl.replacingOccurrences(of: "{folder}", with: folder).replacingOccurrences(of: "{project}", with: s.project)
    }

    /// Subagent dots only while one of them works; finished ones are in the expanded row.
    public static func showsSubDots(_ s: AgentStream) -> Bool {
        (s.subs ?? []).contains(where: \.isWorking)
    }

    // MARK: connection

    /// Short drops are normal (the stream reconnects in a second); say "offline" only after this long.
    public static let offlineGrace: Double = 20

    /// Whether the UI should show the connection problem: never for a blip while data is on screen;
    /// at once when there is nothing to show or the problem needs the user (token, server setup, app update).
    public static func showsOffline(_ c: ConnectionState, offlineSince: Date?, hasData: Bool, now: Date) -> Bool {
        switch c {
        case .live: return false
        case .noToken, .unauthorized, .notConfigured, .unsupportedAPI: return true
        case .idle, .connecting, .retrying:
            guard hasData else { return true }
            guard let since = offlineSince else { return false }
            return now.timeIntervalSince(since) >= offlineGrace
        }
    }

    // MARK: time

    /// 45 s · 12 min · 1 h 20 min
    public static func duration(_ seconds: Double, _ t: Strings) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return t.tr("app.dur.s", ["n": .number(Double(s))], fallback: "\(s) s") }
        if s < 3600 {
            let m = s / 60
            return t.tr("app.dur.m", ["n": .number(Double(m))], fallback: "\(m) min")
        }
        let h = s / 3600, m = s % 3600 / 60
        return t.tr("app.dur.hm", ["h": .number(Double(h)), "m": .number(Double(m))], fallback: "\(h) h \(m) min")
    }

    // MARK: actions

    /// Tool → the board's verb key (TOOL_RU in board.js); Bash shows the command itself.
    static let toolVerb: [String: String] = [
        "Edit": "ui.pravit", "MultiEdit": "ui.pravit", "NotebookEdit": "ui.pravit", "Write": "ui.pishet",
        "Read": "ui.chitaet", "Grep": "ui.ischet_v_kode", "Glob": "ui.ischet_fayly", "WebFetch": "ui.chitaet_sayt",
        "WebSearch": "ui.ischet_v_seti", "Task": "ui.subagent", "Agent": "ui.subagent",
        "SubagentHandback": "ui.subagent_vernulsya", "TodoWrite": "ui.obnovil_plan", "TaskCreate": "ui.obnovil_plan",
        "TaskUpdate": "ui.obnovil_plan",
    ]

    /// "правит app.py", "pytest", "ищет в коде fixtures".
    public static func actionText(_ a: Action, _ t: Strings) -> String {
        let tool = a.tool ?? ""
        let verb: String
        if tool == "Bash" { verb = "" } else if let key = toolVerb[tool] { verb = t.tr(key, fallback: tool) } else { verb = tool }
        let what = a.what ?? (tool == "Bash" ? t.tr("ui.komanda", fallback: "command") : "")
        return [verb, what].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
