import XCTest
@testable import UptimeKit

final class TrayTests: XCTestCase {
    private func streams(_ json: String) throws -> [AgentStream] {
        try UptimeJSON.status(from: Data((#"{"api": 1, "claude": {"streams": "# + json + "}}").utf8)).streams
    }

    func testMoodPicksWhatNeedsYouMost() throws {
        let all = try streams("""
        [{"project": "a", "state": "working"}, {"project": "b", "state": "waiting"},
         {"project": "c", "state": "waiting", "ask": "question"}, {"project": "d", "state": "idle"}]
        """)
        XCTAssertEqual(TrayMood.of(all, offline: false), .dialog)
        XCTAssertEqual(TrayMood.of(Array(all.prefix(2)), offline: false), .waiting)
        XCTAssertEqual(TrayMood.of(Array(all.prefix(1)), offline: false), .working)
        XCTAssertEqual(TrayMood.of(Array(all.suffix(1)), offline: false), .quiet)
        XCTAssertEqual(TrayMood.of([], offline: false), .quiet)
        XCTAssertEqual(TrayMood.of(all, offline: true), .offline) // offline wins: the data is stale
        let perm = try streams(#"[{"project": "p", "state": "waiting", "ask": "permission"}]"#)
        XCTAssertEqual(TrayMood.of(perm, offline: false), .dialog)
    }

    func testEyeColours() {
        XCTAssertEqual([TrayMood.offline, .quiet, .working, .waiting, .dialog].map(\.eyes), [nil, nil, .ok, .warn, .bad])
    }

    func testOnlyRedBlinks() {
        XCTAssertTrue(TrayMood.dialog.eyesLit(at: 10.0, reduceMotion: false))   // 10.0 mod 1.6 = 0.4: lit
        XCTAssertFalse(TrayMood.dialog.eyesLit(at: 11.0, reduceMotion: false))  // 11.0 mod 1.6 = 1.4: dark
        XCTAssertTrue(TrayMood.dialog.eyesLit(at: 11.0, reduceMotion: true))    // Reduce Motion: steady
        for t in stride(from: 0.0, to: 3.2, by: 0.1) {
            XCTAssertTrue(TrayMood.waiting.eyesLit(at: t, reduceMotion: false))
            XCTAssertTrue(TrayMood.working.eyesLit(at: t, reduceMotion: false))
            XCTAssertFalse(TrayMood.quiet.eyesLit(at: t, reduceMotion: false))
        }
    }

    func testEyePixelsAreTheSilhouettesHoles() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sprites-mini", withExtension: "json", subdirectory: "Fixtures"))
        let s = try Sprites.decode(Data(contentsOf: url))
        XCTAssertEqual(s.eyePixels(pose: "sit").map { [$0.x, $0.y] }, [[1, 1], [2, 1]])
        let body = Set(s.silhouette(pose: "sit").map { [$0.x, $0.y] })
        XCTAssertTrue(s.eyePixels(pose: "sit").allSatisfy { !body.contains([$0.x, $0.y]) })
    }
}
