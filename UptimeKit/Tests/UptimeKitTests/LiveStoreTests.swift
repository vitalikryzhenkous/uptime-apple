import XCTest
@testable import UptimeKit

private func status(_ build: String) -> Status {
    try! UptimeJSON.status(from: Data(#"{"api": 1, "build": "\#(build)"}"#.utf8))
}

/// A source whose answers are scripted per attempt.
private final class FakeSource: StatusSource, @unchecked Sendable {
    enum Step { case fail(Error), stream(Status, [ServerEvent], end: Error?) }
    private let lock = NSLock()
    private var steps: [Step]
    private var current: Step?

    init(_ steps: [Step]) { self.steps = steps }

    func status() async throws -> Status {
        let step = lock.withLock { () -> Step? in
            current = steps.isEmpty ? nil : steps.removeFirst()
            return current
        }
        switch step {
        case .fail(let e)?: throw e
        case .stream(let s, _, _)?: return s
        case nil: throw URLError(.notConnectedToInternet)
        }
    }

    func events() -> AsyncThrowingStream<ServerEvent, Error> {
        let step = lock.withLock { current }
        return AsyncThrowingStream { c in
            if case .stream(_, let events, let end)? = step {
                events.forEach { c.yield($0) }
                c.finish(throwing: end)
            } else {
                c.finish()
            }
        }
    }
}

/// Records the backoff delays and stops the loop after `limit` sleeps.
/// true on the first call only: a token that is there once, then removed.
private final class FirstOnly: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.withLock { defer { used = true }; return !used } }
}

private actor Sleeps {
    private(set) var delays: [Int] = []
    let limit: Int
    init(limit: Int) { self.limit = limit }
    func sleep(_ s: Int) throws {
        delays.append(s)
        if delays.count >= limit { throw CancellationError() }
    }
}

final class LiveStoreTests: XCTestCase {
    @MainActor
    func testStatusThenStream() async {
        let source = FakeSource([.stream(status("one"), [.status(status("two")), .ping], end: nil)])
        let sleeps = Sleeps(limit: 1)
        let store = LiveStore(makeSource: { source }, sleep: { try await sleeps.sleep($0) })
        await store.run()
        XCTAssertEqual(store.status?.build, "two")
        XCTAssertNotNil(store.lastUpdate)
        // the stream ended normally → one quick retry
        XCTAssertEqual(store.connection, .retrying(seconds: 1, reason: "stream ended"))
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1])
    }

    @MainActor
    func testBackoffGrowsAndCaps() async {
        let fail = FakeSource.Step.fail(URLError(.timedOut))
        let source = FakeSource(Array(repeating: fail, count: 8))
        let sleeps = Sleeps(limit: 8)
        let store = LiveStore(makeSource: { source }, sleep: { try await sleeps.sleep($0) })
        await store.run()
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30])
        XCTAssertNil(store.status)
    }

    @MainActor
    func testSuccessResetsBackoff() async {
        let source = FakeSource([.fail(URLError(.timedOut)), .fail(URLError(.timedOut)),
                                 .stream(status("ok"), [], end: URLError(.networkConnectionLost)),
                                 .fail(URLError(.timedOut))])
        let sleeps = Sleeps(limit: 4)
        let store = LiveStore(makeSource: { source }, sleep: { try await sleeps.sleep($0) })
        await store.run()
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2, 1, 2])
        XCTAssertEqual(store.status?.build, "ok")
    }

    @MainActor
    func testUnauthorizedStops() async {
        let source = FakeSource([.fail(APIError.unauthorized)])
        let sleeps = Sleeps(limit: 1)
        let store = LiveStore(makeSource: { source }, sleep: { try await sleeps.sleep($0) })
        await store.run()
        XCTAssertEqual(store.connection, .unauthorized)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [])
    }

    @MainActor
    func testUnauthorizedMidStreamStops() async {
        let source = FakeSource([.stream(status("a"), [], end: APIError.unauthorized)])
        let store = LiveStore(makeSource: { source }, sleep: { _ in XCTFail("must not retry") })
        await store.run()
        XCTAssertEqual(store.connection, .unauthorized)
        XCTAssertNil(store.status, "a revoked token must not leave the old cards on screen")
    }

    @MainActor
    func testTokenRemovedClearsCards() async {
        let source = FakeSource([.stream(status("a"), [], end: APIError.notConfigured)])
        let first = FirstOnly()
        let store = LiveStore(makeSource: { first.take() ? source : nil },
                              sleep: { _ in XCTFail("must not retry") })
        await store.run()
        XCTAssertEqual(store.status?.build, "a")  // other stops keep the last cards
        await store.run()  // second start: no token in the Keychain any more
        XCTAssertEqual(store.connection, .noToken)
        XCTAssertNil(store.status)
    }

    @MainActor
    func testNoToken() async {
        let store = LiveStore(makeSource: { nil }, sleep: { _ in XCTFail("must not retry") })
        await store.run()
        XCTAssertEqual(store.connection, .noToken)
    }

    @MainActor
    func testNotConfiguredAndNewerAPIStop() async {
        for (error, expected) in [(APIError.notConfigured, ConnectionState.notConfigured),
                                  (.unsupportedAPI(2), .unsupportedAPI(2))] {
            let source = FakeSource([.fail(error)])
            let store = LiveStore(makeSource: { source }, sleep: { _ in XCTFail("must not retry") })
            await store.run()
            XCTAssertEqual(store.connection, expected)
        }
    }

    func testBackoffTable() {
        XCTAssertEqual((1...8).map { Backoff.seconds(attempt: $0) }, [1, 2, 4, 8, 16, 30, 30, 30])
    }
}
