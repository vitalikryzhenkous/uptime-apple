import XCTest
@testable import UptimeKit

final class PermissionTests: XCTestCase {
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://board.test:8443")!, token: "t0ken", session: URLSession(configuration: config))
    }

    private func body(_ r: URLRequest) -> [String: String] {
        guard let stream = r.httpBodyStream else { return [:] }
        stream.open()
        defer { stream.close() }
        var data = Data(), buf = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private let rid = "fRP2zJmGfsu0O8fwS5a9Gw"

    private func status() throws -> Status {
        try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "ask": "permission", "session": "8d27f42e-cc4",
           "ask_tool": {"tool": "Bash", "what": "touch"}},
          {"project": "b", "state": "waiting", "session": "7d7ebf5f-f31", "pane": "%4"},
          {"project": "c", "state": "working", "session": "9125ecaf-d4c"}]},
         "permissions": [
          {"id": "fRP2zJmGfsu0O8fwS5a9Gw", "session": "8d27f42e-cc4", "tool": "Bash", "what": "touch",
           "command": "touch /tmp/rt-test.txt", "danger": false, "partial": false, "created": 1000, "expires": 1590},
          {"id": "olderolderolderolder01", "session": "8d27f42e-cc4", "tool": "Bash", "what": "ls",
           "command": "ls", "danger": false, "partial": false, "created": 900, "expires": 1490},
          {"id": "T0QVrFFx9o4jzDwMkqGTKw", "session": "7d7ebf5f-f31", "tool": "Bash", "what": "touch",
           "command": "touch x", "danger": false, "partial": false, "created": 1000, "expires": 1590}]}
        """#.utf8))
    }

    func testDecodesAndMatchesTheCard() throws {
        let st = try status()
        XCTAssertEqual(st.permissions?.count, 3)
        let s = st.streams
        XCTAssertEqual(Panel.permission(for: s[0], in: st.permissions, now: 1100)?.id, rid) // the newest of the session's
        XCTAssertNil(Panel.permission(for: s[1], in: st.permissions, now: 1100)) // no dialog on that card any more
        XCTAssertNil(Panel.permission(for: s[2], in: st.permissions, now: 1100))
        XCTAssertNil(Panel.permission(for: s[0], in: st.permissions, now: 1600)) // expired
        XCTAssertNil(Panel.permission(for: s[0], in: nil, now: 1100)) // the board's opt-in is off
    }

    func testWithoutPermissionsStillDecodes() throws {
        let st = try UptimeJSON.status(from: Data(#"{"api": 1}"#.utf8))
        XCTAssertNil(st.permissions)
    }

    func testAllowOnlyWhenSafeAndWhole() throws {
        func req(_ danger: String, _ partial: String) throws -> PermissionRequest {
            try JSONDecoder().decode(PermissionRequest.self, from: Data(
                #"{"id": "fRP2zJmGfsu0O8fwS5a9Gw", "session": "s", "command": "x" \#(danger)\#(partial)}"#.utf8))
        }
        let s = Strings(lang: "en", table: [:])
        XCTAssertTrue(Panel.canAllow(try req(#", "danger": false"#, #", "partial": false"#)))
        XCTAssertNil(Panel.denyOnlyText(try req(#", "danger": false"#, #", "partial": false"#), s))
        XCTAssertFalse(Panel.canAllow(try req(#", "danger": true"#, #", "partial": false"#)))
        XCTAssertEqual(Panel.denyOnlyText(try req(#", "danger": true"#, #", "partial": true"#), s),
                       "A risky command: allow it only in the terminal")
        XCTAssertEqual(Panel.denyOnlyText(try req(#", "danger": false"#, #", "partial": true"#), s),
                       "Not all of it is shown: allow it only in the terminal")
        XCTAssertFalse(Panel.canAllow(try req("", ""))) // flags missing: deny only
    }

    func testPopoverShowsTheWholeCommand() throws {
        let st = try status()
        let r = try XCTUnwrap(st.permissions?.first)
        XCTAssertEqual(Panel.permissionText(r, s: st.streams[0], Strings(lang: "en", table: [:])), "touch /tmp/rt-test.txt")
    }

    func testDecidePosts() async throws {
        StubProtocol.set { _ in (200, Data(#"{"ok": true}"#.utf8)) }
        let r = try await client().decide(.allow, request: rid)
        XCTAssertEqual(r, .done)
        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.url?.absoluteString, "https://board.test:8443/api/v1/permissions/\(rid)")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t0ken")
        XCTAssertEqual(body(req), ["decision": "allow"])
    }

    func testRefusals() async throws {
        for (code, error) in [(409, "decided"), (403, "terminal_only"), (404, "request"), (403, "off")] {
            StubProtocol.set { _ in (code, Data(#"{"ok": false, "error": "\#(error)"}"#.utf8)) }
            let r = try await client().decide(.deny, request: rid)
            XCTAssertEqual(r, .refused(error))
        }
        StubProtocol.set { _ in (401, Data()) }
        do {
            _ = try await client().decide(.deny, request: rid)
            XCTFail("401 should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testBadRequestIdNeverLeaves() async throws {
        StubProtocol.set { _ in (200, Data()) }
        let r = try await client().decide(.allow, request: "../status")
        XCTAssertEqual(r, .refused("request"))
        XCTAssertTrue(StubProtocol.seen.isEmpty)
    }

    func testErrorTexts() {
        let s = Strings(lang: "en", table: [:])
        XCTAssertEqual(Panel.decisionErrorText("decided", s), "Already answered")
        XCTAssertEqual(Panel.decisionErrorText("weird", s), "Couldn't answer (weird)")
    }
}
