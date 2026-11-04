import XCTest
@testable import UptimeKit

final class JumpTests: XCTestCase {
    private func streams(_ json: String) throws -> [AgentStream] {
        try UptimeJSON.status(from: Data((#"{"api": 1, "claude": {"streams": "# + json + "}}").utf8)).streams
    }

    func testDialogFirstThenLongestWait() throws {
        let s = try streams("""
        [{"project": "work", "state": "working", "since": 10},
         {"project": "late", "state": "waiting", "since": 300},
         {"project": "early", "state": "waiting", "since": 100},
         {"project": "ask", "state": "waiting", "ask": "question", "since": 500}]
        """)
        XCTAssertEqual(Panel.jumpTarget(s)?.project, "ask")                       // a dialog holds an agent
        XCTAssertEqual(Panel.jumpTarget(Array(s.prefix(3)))?.project, "early")   // then who waits longest
        XCTAssertNil(Panel.jumpTarget(Array(s.prefix(1))))                       // nobody waits: just the panel
        XCTAssertNil(Panel.jumpTarget([]))
    }
}
