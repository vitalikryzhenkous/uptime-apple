import XCTest
@testable import UptimeKit

final class PopoverTests: XCTestCase {
    private func streams() throws -> [AgentStream] {
        try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "session": "abc123", "pane": "%3", "last_msg": "short"},
          {"project": "b", "state": "waiting", "ask": "question", "session": "abc124", "pane": "%4",
           "ask_text": "Что делаем?", "ask_options": ["Опция + длиннее", "Только опция", ""]},
          {"project": "c", "state": "waiting", "ask": "permission", "ask_tool": {"tool": "Bash", "what": "rm"}},
          {"project": "d", "state": "waiting", "last_msg": "line one\nline two"},
          {"project": "e", "state": "working", "ask_options": ["stale"]}]}}
        """#.utf8)).streams
    }

    func testModes() throws {
        let s = try streams()
        XCTAssertEqual(s.map(Panel.popoverMode), [.reply, .readOnly, .readOnly, .text, .text])
    }

    func testShowAllOnlyWhenTheCardCutsSomething() throws {
        let s = try streams()
        XCTAssertFalse(Panel.showsAll(s[0], text: "short"))
        XCTAssertTrue(Panel.showsAll(s[0], text: String(repeating: "слово ", count: 30)))  // longer than 3 lines
        XCTAssertTrue(Panel.showsAll(s[3], text: "line one\nline two"))                   // paragraphs
        XCTAssertTrue(Panel.showsAll(s[1], text: "Что делаем?"))                          // the options are only there
    }

    func testOptionsOnlyWhileAsking() throws {
        let s = try streams()
        XCTAssertEqual(Panel.questionOptions(s[1]), ["Опция + длиннее", "Только опция"])
        XCTAssertEqual(Panel.questionOptions(s[4]), [])  // not asking any more
    }
}
