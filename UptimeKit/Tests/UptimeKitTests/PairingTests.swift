import XCTest
@testable import UptimeKit

final class PairingTests: XCTestCase {
    private let base = URL(string: "https://board.test:8443")!

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
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

    func testCodeAsTyped() {
        XCTAssertEqual(Pairing.code("461 809"), "461809")
        XCTAssertEqual(Pairing.code(" 461-809\n"), "461809")
        XCTAssertNil(Pairing.code("46180"))
        XCTAssertNil(Pairing.code("4618090"))
        XCTAssertNil(Pairing.code("46a809"))
        XCTAssertNil(Pairing.code("٤٦١٨٠٩")) // only ASCII digits
    }

    func testLinkFromPairTool() throws {
        let l = try XCTUnwrap(Pairing.link(URL(string: "uptime://pair?code=461809&url=https%3A%2F%2Fboard.test%3A8443")!))
        XCTAssertEqual(l, Pairing.Link(code: "461809", baseURL: base))
        XCTAssertEqual(Pairing.link(URL(string: "uptime://pair?code=461809")!), Pairing.Link(code: "461809", baseURL: nil))
    }

    func testLinkRefusesTheRest() {
        XCTAssertNil(Pairing.link(URL(string: "https://pair?code=461809")!))
        XCTAssertNil(Pairing.link(URL(string: "uptime://other?code=461809")!))
        XCTAssertNil(Pairing.link(URL(string: "uptime://pair?code=12")!))
        // a plain-HTTP board is dropped, not trusted: the app keeps the address it has
        XCTAssertEqual(Pairing.link(URL(string: "uptime://pair?code=461809&url=http://evil.test")!)?.baseURL, nil)
    }

    func testHttpsBaseOnlyHostAndPort() {
        XCTAssertEqual(Pairing.httpsBase("https://user:pw@board.test:8443/x?y=1#z"), base)
        XCTAssertNil(Pairing.httpsBase("http://board.test"))
        XCTAssertNil(Pairing.httpsBase("board.test"))
    }

    func testClaimPostsCodeWithoutToken() async throws {
        StubProtocol.set { _ in (200, Data(#"{"ok": true, "device": "7e5de1", "token": "dev-tok"}"#.utf8)) }
        let r = try await Pairing.claim(code: "461809", name: "Mac", baseURL: base, session: session())
        XCTAssertEqual(r, .paired(token: "dev-tok"))
        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.url?.absoluteString, "https://board.test:8443/api/v1/pair/claim")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body(req), ["code": "461809", "name": "Mac"])
    }

    func testClaimRefusals() async throws {
        for (status, reason) in [(403, "code"), (429, "rate"), (404, "old_board"), (405, "old_board")] {
            StubProtocol.set { _ in (status, Data(#"{"ok": false}"#.utf8)) }
            let r = try await Pairing.claim(code: "461809", name: "Mac", baseURL: base, session: session())
            XCTAssertEqual(r, .refused(reason), "HTTP \(status)")
        }
    }

    func testClaimWithoutTokenIsAnError() async {
        StubProtocol.set { _ in (200, Data(#"{"ok": true}"#.utf8)) }
        do {
            _ = try await Pairing.claim(code: "461809", name: "Mac", baseURL: base, session: session())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func testCommandForTheWizard() {
        XCTAssertEqual(Pairing.command(baseURL: base, user: " lenovo "),
                       "ssh lenovo@board.test '~/apps/uptime-board/tools/pair.py --url https://board.test:8443'")
        XCTAssertEqual(Pairing.command(baseURL: base, user: ""),
                       "ssh board.test '~/apps/uptime-board/tools/pair.py --url https://board.test:8443'")
        XCTAssertEqual(Pairing.command(baseURL: base, user: "x; rm -rf ~"), // never pasted into the shell as is
                       "ssh board.test '~/apps/uptime-board/tools/pair.py --url https://board.test:8443'")
    }
}
