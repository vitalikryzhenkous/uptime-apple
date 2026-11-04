import XCTest
@testable import UptimeKit

/// Answers URLSession requests from a handler set by the test; the lock keeps TSan happy.
final class StubProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _seen: [URLRequest] = []

    static func set(_ handler: @escaping Handler) { lock.withLock { _handler = handler; _seen = [] } }
    static var seen: [URLRequest] { lock.withLock { _seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { () -> Handler? in Self._seen.append(request); return Self._handler }
        let (code, body) = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func client(token: String = "t0ken") -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://board.test:8443")!, token: token, session: URLSession(configuration: config))
    }

    func testStatusSendsTokenAndDecodes() async throws {
        StubProtocol.set { _ in (200, Data(#"{"api": 1, "build": "b1"}"#.utf8)) }
        let s = try await client().status()
        XCTAssertEqual(s.build, "b1")
        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.url?.absoluteString, "https://board.test:8443/api/v1/status")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t0ken")
    }

    func testErrorCodes() async {
        for (code, expected) in [(401, APIError.unauthorized), (503, .notConfigured), (502, .badStatus(502))] {
            StubProtocol.set { _ in (code, Data()) }
            do {
                _ = try await client().status()
                XCTFail("\(code) should throw")
            } catch {
                XCTAssertEqual(error as? APIError, expected)
            }
        }
    }

    func testNewerAPIIsRejected() async {
        StubProtocol.set { _ in (200, Data(#"{"api": 2}"#.utf8)) }
        do {
            _ = try await client().status()
            XCTFail("api 2 should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unsupportedAPI(2))
        }
    }

    func testEventsStream() async throws {
        let body = "event: status\nid: 1\ndata: {\"api\": 1, \"build\": \"s1\"}\n\nevent: ping\ndata: 1\n\n"
        StubProtocol.set { _ in (200, Data(body.utf8)) }
        var builds: [String] = [], pings = 0
        for try await e in client().events() {
            switch e {
            case .status(let s): builds.append(s.build ?? "")
            case .ping: pings += 1
            }
        }
        XCTAssertEqual(builds, ["s1"])
        XCTAssertEqual(pings, 1)
        let req = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(req.url?.path, "/api/v1/events")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(req.timeoutInterval, ServerConfig.streamIdleTimeout)
    }

    func testEventsUnauthorized() async {
        StubProtocol.set { _ in (401, Data()) }
        do {
            for try await _ in client().events() {}
            XCTFail("401 should throw")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testMemoryTokenStore() throws {
        let store = MemoryTokenStore()
        XCTAssertNil(store.read())
        try store.write("abc")
        XCTAssertEqual(store.read(), "abc")
        try store.write("")
        XCTAssertNil(store.read())
    }
}
