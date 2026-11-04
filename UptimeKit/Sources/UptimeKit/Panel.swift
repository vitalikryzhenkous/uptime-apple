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
                line += since(s.started)
            }
            return line
        case .idle:
            return t.tr("app.state.idle", fallback: "idle") + since(s.since)
        case .open, .unknown:
            return t.tr("app.state.open", fallback: "open")
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
