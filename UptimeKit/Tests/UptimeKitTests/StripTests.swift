import XCTest
@testable import UptimeKit

final class StripTests: XCTestCase {
    func testPulseByState() throws {
        let s = try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "ask": "permission"}, {"project": "b", "state": "waiting"},
          {"project": "c", "state": "working"}, {"project": "d", "state": "idle"}, {"project": "e", "state": "open"}]}}
        """#.utf8)).streams
        XCTAssertEqual(s.map(Panel.pulsePeriod), [1.4, 1.4, 2.8, nil, nil])
        // the strip's colour is the old dot's: red permission, yellow waiting, green working, grey otherwise
        XCTAssertEqual(s.map(Panel.dot), [.bad, .warn, .ok, .muted, .muted])
    }
}
