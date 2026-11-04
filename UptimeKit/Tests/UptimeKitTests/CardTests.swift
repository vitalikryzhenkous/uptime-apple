import XCTest
@testable import UptimeKit

final class CardTests: XCTestCase {
    private let ru = Strings(lang: "ru", table: [
        "app.ask.permission": "просит {tool}", "app.dur.m": "{n} мин",
        "app.actions.one": "{n} действие", "app.actions.few": "{n} действия", "app.actions.many": "{n} действий",
    ])

    private func streams(_ json: String) throws -> [AgentStream] {
        try UptimeJSON.status(from: Data(#"{"api": 1, "claude": {"streams": \#(json)}}"#.utf8)).streams
    }

    func testAskLine() throws {
        let s = try streams("""
        [{"project": "a", "state": "waiting", "ask": "permission", "ask_tool": {"tool": "Bash", "what": "git push"}},
         {"project": "b", "state": "waiting", "ask": "permission", "ask_tool": {"tool": "Bash", "what": "git push"},
          "ask_text": "git push --force origin main"},
         {"project": "c", "state": "waiting", "ask": "idle", "last_msg": "…Should I merge?"},
         {"project": "d", "state": "waiting", "ask": "idle"},
         {"project": "e", "state": "working", "last_msg": "old"},
         {"project": "f", "state": "waiting", "ask": "permission"}]
        """)
        XCTAssertEqual(s.map { Panel.askLine($0, ru) }, [
            "просит Bash · git push",
            "просит Bash · git push --force origin main", // the opt-in command beats the short form
            "…Should I merge?",
            nil,
            nil,   // working: nothing waits
            nil,   // an older board without ask_tool
        ])
    }

    func testProgress() throws {
        let s = try streams("""
        [{"project": "a", "state": "working", "plan": {"done": 3, "total": 7, "now": "Write tests"}},
         {"project": "b", "state": "working", "plan": {"done": 9, "total": 7, "now": ""}},
         {"project": "c", "state": "working", "plan": {"done": 0, "total": 0}},
         {"project": "d", "state": "working"}]
        """)
        XCTAssertEqual(Panel.planProgress(s[0]), Panel.Progress(done: 3, total: 7, step: "Write tests"))
        XCTAssertEqual(Panel.planProgress(s[0])!.fraction, 3.0 / 7, accuracy: 0.001)
        XCTAssertEqual(Panel.planProgress(s[1]), Panel.Progress(done: 7, total: 7, step: nil))
        XCTAssertNil(Panel.planProgress(s[2]))
        XCTAssertNil(Panel.planProgress(s[3]))
    }

    func testTurnLine() throws {
        let s = try streams("""
        [{"project": "a", "state": "working", "since": 9280, "turn_actions": 24},
         {"project": "b", "state": "working", "since": 9280},
         {"project": "c", "state": "waiting", "since": 9280, "turn_actions": 3}]
        """)
        XCTAssertEqual(Panel.turnLine(s[0], now: 10_000, ru), "12 мин · 24 действия")
        XCTAssertEqual(Panel.turnLine(s[1], now: 10_000, ru), "12 мин")
        XCTAssertNil(Panel.turnLine(s[2], now: 10_000, ru))
    }

    func testLinks() throws {
        let st = try UptimeJSON.status(from: Data(#"""
        {"api": 1,
         "claude": {"streams": [{"project": "a", "state": "waiting", "rc": "session_01AbC"},
                                {"project": "b", "state": "waiting", "rc": "../evil"}]},
         "git": {"apps/a": {"ci": "fail", "ci_url": "https://github.com/o/r/actions/runs/41",
                            "prs": [{"n": 7, "checks": "ok", "url": "https://github.com/o/r/pull/7"},
                                    {"n": 8, "url": "https://evil.example/o/r/pull/8"}]}}}
        """#.utf8))
        XCTAssertEqual(st.streams[0].claudeURL?.absoluteString, "https://claude.ai/code/session_01AbC")
        XCTAssertNil(st.streams[1].claudeURL)
        let g = try XCTUnwrap(st.git?["apps/a"])
        XCTAssertEqual(g.ciState, .fail)
        XCTAssertEqual(g.ciLink?.absoluteString, "https://github.com/o/r/actions/runs/41")
        XCTAssertEqual(g.prs?.map { $0.link?.absoluteString }, ["https://github.com/o/r/pull/7", nil])
    }

    func testConnectCommand() throws {
        let s = try streams(#"[{"project": "uptime-board", "folder": "apps/uptime-board", "state": "waiting"}, {"project": "x;rm", "state": "open"}]"#)
        let tpl = "ssh m920q -t 'cd ~/{folder} && claude --continue'"
        XCTAssertEqual(Panel.connectCommand(tpl, s[0]), "ssh m920q -t 'cd ~/apps/uptime-board && claude --continue'")
        XCTAssertNil(Panel.connectCommand(tpl, s[1]))   // unsafe name → no command at all
        XCTAssertNil(Panel.connectCommand("  ", s[0]))  // no template → no button
    }
}

final class ResetsTests: XCTestCase {
    private func limits(_ json: String) throws -> Limits {
        try JSONDecoder().decode(Limits.self, from: Data(json.utf8))
    }

    func testSuggestsResetsFrom80() throws {
        XCTAssertFalse(Panel.suggestsResets(try limits(#"{"h5": {"pct": 79}, "d7": {"pct": 50}}"#)))
        XCTAssertTrue(Panel.suggestsResets(try limits(#"{"h5": {"pct": 12}, "d7": {"pct": 80}}"#)))
        XCTAssertTrue(Panel.suggestsResets(try limits(#"{"h5": {"pct": 95}, "d7": null}"#)))
        XCTAssertFalse(Panel.suggestsResets(try limits(#"{"h5": null, "d7": null}"#)))
    }
}
