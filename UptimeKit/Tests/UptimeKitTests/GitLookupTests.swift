import XCTest
@testable import UptimeKit

/// The live server keys `git` by repo name while sessions carry "apps/<repo>" — the shape seen on the M920q.
final class GitLookupTests: XCTestCase {
    func testLookupLikeTheBoard() throws {
        let st = try UptimeJSON.status(from: Data(#"""
        {"api": 1,
         "claude": {"streams": [
           {"project": "babyloop", "folder": "apps/babyloop", "state": "waiting"},
           {"project": "uptime-board ×2", "folder": "apps/uptime-board", "state": "working"},
           {"project": "nothing", "folder": "apps/nothing", "state": "open"},
           {"project": "remote-thing", "state": "open"}]},
         "git": {"babyloop": {"ci": "ok"}, "uptime-board": {"ci": "fail"}, "remote-thing": {"ci": "run"}}}
        """#.utf8))
        XCTAssertEqual(st.streams.map { st.gitInfo(for: $0)?.ciState }, [.ok, .fail, nil, .run])
    }
}
