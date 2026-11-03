import XCTest
@testable import UptimeKit

final class StatusDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Status {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try UptimeJSON.status(from: Data(contentsOf: url))
    }

    func testFullStatus() throws {
        let s = try fixture("status-full")
        XCTAssertEqual(s.api, UptimeJSON.supportedAPI)
        XCTAssertEqual(s.persona?.name, "Buddy")
        XCTAssertEqual(s.build, "dcebcb6e")
        XCTAssertEqual(s.serverTime ?? 0, 1793722879.09, accuracy: 0.01)

        // sessions
        XCTAssertEqual(s.streams.count, 2)
        let a = s.streams[0], b = s.streams[1]
        XCTAssertEqual(a.id, "apps/demo-api")
        XCTAssertEqual(a.stateKind, .working)
        XCTAssertFalse(a.asksPermission)
        XCTAssertEqual(a.ctx?.pct, 13)
        XCTAssertEqual(a.ctx?.turnsLeft, 87)
        XCTAssertEqual(a.compact?.trigger, "auto")
        XCTAssertEqual(a.plan?.total, 5)
        XCTAssertEqual(a.tasks?.count, 2)
        XCTAssertEqual(a.subs?.filter(\.isWorking).count, 1)
        XCTAssertEqual(a.subs?.first?.doing?.tool, "Grep")
        XCTAssertNil(a.subs?.last?.doing)
        XCTAssertEqual(b.stateKind, .waiting)
        XCTAssertTrue(b.asksPermission)
        XCTAssertNil(b.doing)
        XCTAssertNil(b.compact)
        XCTAssertEqual(b.ctx?.limit, 92)

        // limits
        XCTAssertEqual(s.claude?.limits?.d7?.pct, 70)
        XCTAssertEqual(s.claude?.limits?.h5?.reset, 1793739600)

        // git: folder keys stay exactly as sent (no snake-case rewriting)
        XCTAssertEqual(s.git?["apps/demo-api"]?.ciState, .run)
        XCTAssertEqual(s.git?["apps/demo-api"]?.prs?.first?.checksState, .ok)
        XCTAssertEqual(s.git?["apps/demo-api"]?.dirty, 3)
        XCTAssertNotNil(s.git?["apps/demo_web"])
        XCTAssertNil(s.git?["apps/demo_web"]?.ciState)

        // health
        XCTAssertEqual(s.health?.count, 2)
        XCTAssertEqual(s.health?[1].detailKey, "health.timeout")
        XCTAssertEqual(s.health?[1].detailVars?["s"]?.text, "5")

        // machine and weather
        XCTAssertNil(s.machine?.temp)
        XCTAssertEqual(s.machine?.load, 4.1)
        XCTAssertEqual(s.weather?.group, "cloudy")

        // the cat
        let cat = try XCTUnwrap(s.cat)
        XCTAssertEqual(cat.look?.pose, "lie")
        XCTAssertEqual(cat.look?.overlays, ["scarf"])
        XCTAssertEqual(cat.pet?.love, 75)
        XCTAssertNil(s.nikolai?[1].look)
        XCTAssertEqual(s.nikolai?[1].buttons?.last?.log, true)
        XCTAssertEqual(s.nikolai?[1].vars?["n"]?.text, "3")

        // notifications: unknown kinds decode, they just map to .unknown
        XCTAssertEqual(s.notifications?.map(\.kindValue), [.done, .limit, .unknown])
        XCTAssertEqual(s.notifications?[0].vars?["who"]?.text, "demo-api")
        XCTAssertEqual(s.notifications?[1].vars?["pct"]?.text, "80")
    }

    func testMinimalStatus() throws {
        let s = try fixture("status-minimal")
        XCTAssertEqual(s.ok, false)
        XCTAssertNotNil(s.error)
        XCTAssertTrue(s.streams.isEmpty)
        XCTAssertNil(s.claude?.limits?.h5)
        XCTAssertEqual(s.claude?.limits?.d7?.pct, 12)
        XCTAssertNil(s.weather)
        XCTAssertEqual(s.git?.count, 0)
        XCTAssertEqual(s.cat?.look?.overlays, [])
        XCTAssertNil(s.cat?.look?.mark)
    }

    func testMissingOptionalBlocks() throws {
        let s = try UptimeJSON.status(from: Data(#"{"api": 1}"#.utf8))
        XCTAssertNil(s.claude)
        XCTAssertTrue(s.streams.isEmpty)
        XCTAssertNil(s.cat)
    }

    func testJSONValueText() throws {
        let vars = try JSONDecoder().decode([String: JSONValue].self,
                                            from: Data(#"{"a": 5, "b": 2.5, "c": "x", "d": true, "e": null}"#.utf8))
        XCTAssertEqual(vars["a"]?.text, "5")
        XCTAssertEqual(vars["b"]?.text, "2.5")
        XCTAssertEqual(vars["c"]?.text, "x")
        XCTAssertEqual(vars["d"]?.text, "true")
        XCTAssertEqual(vars["e"]?.text, "")
    }
}
