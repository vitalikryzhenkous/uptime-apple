import XCTest
@testable import UptimeKit

final class PanelTests: XCTestCase {
    private let ru = Strings(lang: "ru", table: [
        "app.state.permission": "ждёт разрешения", "app.state.waiting": "ждёт тебя", "app.state.working": "работает",
        "app.state.idle": "простой", "app.state.open": "открыта",
        "app.dur.s": "{n} с", "app.dur.m": "{n} мин", "app.dur.hm": "{h} ч {m} мин",
        "app.subs.one": "{n} субагент", "app.subs.few": "{n} субагента", "app.subs.many": "{n} субагентов",
        "ctx.turns.one": "≈{n} ход до заполнения", "ctx.turns.few": "≈{n} хода до заполнения",
        "ctx.turns.many": "≈{n} ходов до заполнения",
        "ui.pravit": "правит", "ui.ischet_v_kode": "ищет в коде", "ui.komanda": "команда",
    ])

    private func streams(_ json: String) throws -> [AgentStream] {
        try UptimeJSON.status(from: Data(#"{"api": 1, "claude": {"streams": \#(json)}}"#.utf8)).streams
    }

    func testThresholdsMatchBoard() {
        XCTAssertEqual([10, 79.9, 80, 94, 95].map(Panel.h5Level), [.ok, .ok, .warn, .warn, .bad])
        XCTAssertEqual([10, 69, 70, 95].map(Panel.weekLevel), [.muted, .muted, .warn, .bad])
        XCTAssertEqual([69.9, 70].map(Panel.weekIsBig), [false, true])
        XCTAssertEqual([13, 70, 84, 85, 91].map(Panel.ctxLevel), [.ok, .warn, .warn, .bad, .bad])
    }

    func testStableOrderByName() throws {
        let list = try streams("""
        [{"project": "zeta", "state": "working"},
         {"project": "idle1", "state": "idle"},
         {"project": "late", "state": "waiting", "since": 200},
         {"project": "alpha", "state": "working"},
         {"project": "ask", "state": "waiting", "ask": "permission", "since": 300},
         {"project": "early", "state": "waiting", "since": 100},
         {"project": "o", "state": "open"}]
        """)
        // by name only: a card never jumps when its state changes (the state is in its colour and words)
        XCTAssertEqual(Panel.sorted(list).map(\.project), ["alpha", "ask", "early", "idle1", "late", "o", "zeta"])
        XCTAssertEqual(Panel.waitingCount(list), 3)
        XCTAssertEqual(list.map(Panel.dot), [.ok, .muted, .warn, .ok, .bad, .warn, .muted])
    }

    func testStateLines() throws {
        let now = 10_000.0
        let list = try streams("""
        [{"project": "a", "state": "waiting", "since": 9820},
         {"project": "b", "state": "waiting", "ask": "permission", "since": 9990},
         {"project": "c", "state": "working", "started": 5000,
          "subs": [{"id": "1", "state": "working"}, {"id": "2", "state": "working"}, {"id": "3", "state": "done"}]},
         {"project": "d", "state": "working", "started": 5000, "ctx": {"pct": 91, "turns_left": 2},
          "subs": [{"id": "1", "state": "working"}]},
         {"project": "e", "state": "working", "started": 5200, "ctx": {"pct": 72, "turns_left": null}},
         {"project": "f", "state": "open"}]
        """)
        let lines = list.map { Panel.stateLine($0, now: now, ru) }
        XCTAssertEqual(lines, [
            "ждёт тебя · 3 мин",
            "ждёт разрешения · 10 с",
            "работает · 2 субагента",
            "работает · ≈2 хода до заполнения", // context warning beats subagents
            "работает · 1 ч 20 мин",            // high context but no forecast yet → time
            "открыта",
        ])
    }

    func testEnglishFallbackWithoutBoardKeys() throws {
        let bare = Strings(lang: "en", table: [:])
        let s = try streams(#"[{"project": "a", "state": "working", "subs": [{"id": "1", "state": "working"}]}]"#)
        XCTAssertEqual(Panel.stateLine(s[0], now: 0, bare), "working · 1 subagents")
        XCTAssertEqual(Panel.duration(4_000, bare), "1 h 6 min")
    }

    func testTitle() throws {
        let s = try streams(#"[{"project": "uptime-board", "state": "open", "count": 2}, {"project": "x", "state": "open"}]"#)
        XCTAssertEqual(s.map(Panel.title), ["uptime-board ×2", "x"])
    }

    func testDurations() {
        XCTAssertEqual([0, 59, 60, 3599, 3600, 4_800, -5].map { Panel.duration($0, ru) },
                       ["0 с", "59 с", "1 мин", "59 мин", "1 ч 0 мин", "1 ч 20 мин", "0 с"])
    }

    func testActionText() {
        XCTAssertEqual(Panel.actionText(Action(tool: "Edit", what: "app.py", ts: nil), ru), "правит app.py")
        XCTAssertEqual(Panel.actionText(Action(tool: "Bash", what: "pytest", ts: nil), ru), "pytest")
        XCTAssertEqual(Panel.actionText(Action(tool: "Bash", what: nil, ts: nil), ru), "команда")
        XCTAssertEqual(Panel.actionText(Action(tool: "Grep", what: "fixtures", ts: nil), ru), "ищет в коде fixtures")
        XCTAssertEqual(Panel.actionText(Action(tool: "MysteryTool", what: "x", ts: nil), ru), "MysteryTool x")
    }

    @MainActor
    func testServerClockOffset() async {
        let source = OneShot(value: try! UptimeJSON.status(from: Data(#"{"api": 1, "server_time": 4102444800}"#.utf8)))
        let store = LiveStore(makeSource: { source }, sleep: { _ in throw CancellationError() })
        await store.run()
        XCTAssertEqual(store.serverNow(Date()), 4102444800, accuracy: 5)
    }
}

private struct OneShot: StatusSource {
    let value: Status
    func status() async throws -> Status { value }
    func events() -> AsyncThrowingStream<ServerEvent, Error> { AsyncThrowingStream { $0.finish() } }
}
