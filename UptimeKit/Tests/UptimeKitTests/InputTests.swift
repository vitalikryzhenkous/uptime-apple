import XCTest
@testable import UptimeKit

final class InputTests: XCTestCase {
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

    private func streams() throws -> [AgentStream] {
        try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "session": "abc123", "pane": "%3", "ctx": {"pct": 74}},
          {"project": "b", "state": "waiting", "ask": "permission", "session": "abc124", "pane": "%4"},
          {"project": "c", "state": "working", "session": "abc125", "pane": "%5"},
          {"project": "d", "state": "waiting", "session": "abc126"},
          {"project": "e", "state": "waiting", "session": "abc127", "pane": "%7", "remote": true},
          {"project": "f", "state": "waiting", "session": "abc128", "pane": "%8", "ctx": {"pct": 40}}]}}
        """#.utf8)).streams
    }

    func testReplyOnlyWhenWaitingInTmux() throws {
        let s = try streams()
        XCTAssertEqual(s.map(Panel.canReply), [true, false, false, false, false, true]) // never a permission dialog
        XCTAssertEqual(s.map(Panel.offersCompact), [true, false, false, false, false, false]) // ≥70 % context
    }

    func testDraftRules() {
        XCTAssertEqual(AgentInput.problem("  "), .empty)
        XCTAssertEqual(AgentInput.problem("/clear"), .command)
        XCTAssertEqual(AgentInput.problem("!ls"), .command)
        XCTAssertEqual(AgentInput.problem("# note"), .command)
        XCTAssertEqual(AgentInput.problem(String(repeating: "x", count: 501)), .tooLong)
        XCTAssertEqual(AgentInput.problem("a\u{1b}[A"), .tooLong)
        XCTAssertNil(AgentInput.problem("да, мержи"))
        XCTAssertNil(AgentInput.problem("путь /tmp ок")) // a slash inside is fine
    }

    func testSendPostsReply() async throws {
        StubProtocol.set { _ in (200, Data(#"{"ok": true, "sent": 9}"#.utf8)) }
        let r = try await client().send(.reply("  да, мержи "), to: "abc123")
        XCTAssertEqual(r, .sent)
        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.url?.absoluteString, "https://board.test:8443/api/v1/sessions/abc123/input")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t0ken")
        XCTAssertEqual(body(req), ["kind": "reply", "text": "да, мержи"])
    }

    func testCompactBody() async throws {
        StubProtocol.set { _ in (200, Data(#"{"ok": true}"#.utf8)) }
        _ = try await client().send(.compact, to: "abc123")
        XCTAssertEqual(body(try XCTUnwrap(StubProtocol.seen.first)), ["kind": "compact"])
    }

    func testRefusalsAndErrors() async throws {
        StubProtocol.set { _ in (409, Data(#"{"ok": false, "error": "not_waiting"}"#.utf8)) }
        let r = try await client().send(.reply("ok"), to: "abc123")
        XCTAssertEqual(r, .refused("not_waiting"))
        StubProtocol.set { _ in (429, Data("<html>".utf8)) }
        let r2 = try await client().send(.reply("ok"), to: "abc123")
        XCTAssertEqual(r2, .refused("http_429"))
        StubProtocol.set { _ in (401, Data()) }
        do {
            _ = try await client().send(.reply("ok"), to: "abc123")
            XCTFail("401 should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testBadSessionIdNeverLeaves() async throws {
        StubProtocol.set { _ in (200, Data()) }
        let r = try await client().send(.reply("ok"), to: "../status")
        XCTAssertEqual(r, .refused("session"))
        XCTAssertTrue(StubProtocol.seen.isEmpty)
    }

    func testErrorTexts() {
        let s = Strings(lang: "en", table: [:])
        XCTAssertEqual(Panel.inputErrorText("too_fast", s), "Just sent — wait a moment")
        XCTAssertEqual(Panel.inputErrorText("weird", s), "Couldn't send (weird)")
    }
}
