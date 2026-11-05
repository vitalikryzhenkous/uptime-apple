import XCTest
@testable import UptimeKit

final class PermissionNoticeTests: XCTestCase {
    private let en = Strings(lang: "en", table: [:])
    private let rid = "fRP2zJmGfsu0O8fwS5a9Gw"

    /// Card "a" asks (two requests, the newer one counts), "b" asks with a risky command, "c" works.
    private func status(_ permissions: String = """
        [{"id": "fRP2zJmGfsu0O8fwS5a9Gw", "session": "8d27f42e-cc4", "tool": "Bash", "command": "touch /tmp/rt-test.txt",
          "danger": false, "partial": false, "created": 1000, "expires": 1590},
         {"id": "olderolderolderolder01", "session": "8d27f42e-cc4", "tool": "Bash", "command": "ls",
          "danger": false, "partial": false, "created": 900, "expires": 1490},
         {"id": "T0QVrFFx9o4jzDwMkqGTKw", "session": "7d7ebf5f-f31", "tool": "Bash", "command": "rm -rf /tmp/rt-x",
          "danger": true, "partial": false, "created": 1010, "expires": 1200}]
        """) throws -> Status {
        try UptimeJSON.status(from: Data("""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "folder": "apps/a", "state": "waiting", "ask": "permission", "session": "8d27f42e-cc4"},
          {"project": "b", "folder": "apps/b", "state": "waiting", "ask": "permission", "session": "7d7ebf5f-f31"},
          {"project": "c", "state": "working", "session": "9125ecaf-d4c"}]},
         "permissions": \(permissions)}
        """.utf8))
    }

    func testOneNoticePerCardWithTheNewestRequest() throws {
        let ch = Panel.permissionNotices(try status(), shown: [], now: 1100, en)
        XCTAssertEqual(ch.post.map(\.id), [rid, "T0QVrFFx9o4jzDwMkqGTKw"])
        XCTAssertEqual(ch.post.map(\.streamID), ["apps/a", "apps/b"])
        XCTAssertEqual(ch.post[0].title, "a asks for permission")
        XCTAssertEqual(ch.post[0].body, "touch /tmp/rt-test.txt")
        XCTAssertEqual(ch.withdraw, [])
    }

    func testRiskySaysWhyOnlyDeny() throws {
        let b = try XCTUnwrap(Panel.permissionNotices(try status(), shown: [], now: 1100, en).post.last)
        XCTAssertEqual(b.body, "rm -rf /tmp/rt-x\nA risky command: allow it only in the terminal")
    }

    func testEachRequestOnce() throws {
        let ch = Panel.permissionNotices(try status(), shown: [rid], now: 1100, en)
        XCTAssertEqual(ch.post.map(\.id), ["T0QVrFFx9o4jzDwMkqGTKw"])
        XCTAssertEqual(ch.withdraw, [])
    }

    func testWithdrawsAnsweredAndExpired() throws {
        // b's request expired (1200), a's was answered in the terminal: only the older "ls" one is left for a
        let st = try status("""
            [{"id": "olderolderolderolder01", "session": "8d27f42e-cc4", "command": "ls",
              "danger": false, "partial": false, "created": 900, "expires": 1490},
             {"id": "T0QVrFFx9o4jzDwMkqGTKw", "session": "7d7ebf5f-f31", "command": "rm -rf /tmp/rt-x",
              "danger": true, "partial": false, "created": 1010, "expires": 1200}]
            """)
        let ch = Panel.permissionNotices(st, shown: [rid, "T0QVrFFx9o4jzDwMkqGTKw"], now: 1300, en)
        XCTAssertEqual(ch.withdraw, ["T0QVrFFx9o4jzDwMkqGTKw", rid])
        XCTAssertEqual(ch.post.map(\.id), ["olderolderolderolder01"])
    }

    func testOptInOffWithdrawsAll() throws {
        let st = try UptimeJSON.status(from: Data(#"{"api": 1, "claude": {"streams": []}}"#.utf8))
        let ch = Panel.permissionNotices(st, shown: [rid], now: 1100, en)
        XCTAssertEqual(ch, Panel.NoticeChanges(post: [], withdraw: [rid]))
    }

    func testOfflineChangesNothing() {
        XCTAssertEqual(Panel.permissionNotices(nil, shown: [rid], now: 1100, en), Panel.NoticeChanges(post: [], withdraw: []))
    }

    func testLongCommandIsCut() throws {
        let long = String(repeating: "x", count: 400)
        let st = try status("""
            [{"id": "\(rid)", "session": "8d27f42e-cc4", "command": "\(long)", "danger": false, "partial": false,
              "created": 1000, "expires": 1590}]
            """)
        let body = try XCTUnwrap(Panel.permissionNotices(st, shown: [], now: 1100, en).post.first).body
        XCTAssertEqual(body.count, Panel.noticeBodyLimit)
        XCTAssertTrue(body.hasSuffix("…"))
    }

    func testTitleFromTheBoardsStrings() throws {
        let ru = Strings(lang: "ru", table: ["app.notify.perm.title": "{project}: просит разрешение"])
        XCTAssertEqual(Panel.permissionNotices(try status(), shown: [], now: 1100, ru).post.first?.title, "a: просит разрешение")
    }
}
