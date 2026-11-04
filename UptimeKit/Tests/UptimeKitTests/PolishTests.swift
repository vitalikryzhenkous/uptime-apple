import XCTest
@testable import UptimeKit

final class PolishTests: XCTestCase {
    func testOfflineIsHiddenForBlips() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func shows(_ c: ConnectionState, since: Date?, data: Bool, at sec: Double) -> Bool {
            Panel.showsOffline(c, offlineSince: since, hasData: data, now: t0.addingTimeInterval(sec))
        }
        let retry = ConnectionState.retrying(seconds: 1, reason: "connection lost")
        XCTAssertFalse(shows(.live, since: nil, data: true, at: 0))
        XCTAssertFalse(shows(retry, since: t0, data: true, at: 5))        // a blip with data on screen
        XCTAssertFalse(shows(.connecting, since: t0, data: true, at: 19))
        XCTAssertTrue(shows(retry, since: t0, data: true, at: 20))         // long enough to say so
        XCTAssertTrue(shows(.connecting, since: t0, data: false, at: 0))   // nothing to show yet
        XCTAssertTrue(shows(.unauthorized, since: t0, data: true, at: 0))  // needs the user now
        XCTAssertTrue(shows(.noToken, since: nil, data: false, at: 0))
    }

    func testSubDotsOnlyWhileOneWorks() throws {
        let s = try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "working", "subs": [{"id": "1", "state": "done"}, {"id": "2", "state": "done"}]},
          {"project": "b", "state": "working", "subs": [{"id": "1", "state": "done"}, {"id": "2", "state": "working"}]},
          {"project": "c", "state": "working"}]}}
        """#.utf8)).streams
        XCTAssertEqual(s.map(Panel.showsSubDots), [false, true, false])
    }

    func testWorkingShowsThisTurnNotTheSession() throws {
        let s = try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [{"project": "a", "state": "working", "started": 1000, "since": 9400}]}}
        """#.utf8)).streams[0]
        XCTAssertEqual(Panel.stateLine(s, now: 10_000, Strings(lang: "en", table: [:])), "working · 10 min")
    }

    func testSilhouette() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sprites-mini", withExtension: "json", subdirectory: "Fixtures"))
        let sp = try Sprites.decode(Data(contentsOf: url))
        // sit: ".oo." "oeeo" "ootT" → eyes are holes, the B frame (T) is left out, the A frame (t) stays
        let px = sp.silhouette().map { "\($0.x),\($0.y)" }
        XCTAssertEqual(px, ["1,0", "2,0", "0,1", "3,1", "0,2", "1,2", "2,2"])
    }

    func testReadableNetworkErrors() {
        XCTAssertEqual(LiveStore.describe(URLError(.networkConnectionLost)), "connection lost") // the -1005 seen on the Mac
        XCTAssertEqual(LiveStore.describe(URLError(.timedOut)), "timeout")
        XCTAssertEqual(LiveStore.describe(URLError(.badURL)), "network -1000")
    }

    @MainActor
    func testDropsAndOfflineSince() async {
        let ok = try! UptimeJSON.status(from: Data(#"{"api": 1}"#.utf8))
        let source = Dropper(value: ok)
        let store = LiveStore(makeSource: { source }, sleep: { _ in throw CancellationError() })
        await store.run()
        XCTAssertEqual(store.drops, 1)
        XCTAssertEqual(store.lastError, "connection lost")
        XCTAssertNotNil(store.offlineSince)  // left live after the drop
        XCTAssertNotNil(store.status)        // data stays on screen
    }
}

/// Answers /status, then the stream drops at once like the -1005 seen on the Mac.
private struct Dropper: StatusSource {
    let value: Status
    func status() async throws -> Status { value }
    func events() -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: URLError(.networkConnectionLost)) }
    }
}
