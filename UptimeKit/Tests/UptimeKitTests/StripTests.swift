import XCTest
@testable import UptimeKit

final class StripTests: XCTestCase {
    private func streams() throws -> [AgentStream] {
        try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "ask": "permission"}, {"project": "b", "state": "waiting"},
          {"project": "c", "state": "working"}, {"project": "d", "state": "idle"}, {"project": "e", "state": "open"}]}}
        """#.utf8)).streams
    }

    func testShimmerAndTintByState() throws {
        let s = try streams()
        XCTAssertEqual(s.map { Panel.shimmer($0)?.period }, [4.5, 4.5, 9, nil, nil])
        XCTAssertLessThan(Panel.shimmer(s[2])!.strength, Panel.shimmer(s[0])!.strength) // working is fainter
        XCTAssertEqual(s.map(Panel.tint), [0.09, 0.09, 0.06, 0, 0])
        // the colour: red permission, yellow waiting, green working, grey otherwise
        XCTAssertEqual(s.map(Panel.dot), [.bad, .warn, .ok, .muted, .muted])
    }

    func testSweepThenPause() {
        let sh = Panel.Shimmer(period: 4.5, strength: 0.2)
        XCTAssertEqual(Panel.shimmerPosition(sh, at: 9.0), 0)                       // a sweep starts
        XCTAssertEqual(Panel.shimmerPosition(sh, at: 9.8)!, 0.5, accuracy: 0.001)   // halfway across
        XCTAssertNil(Panel.shimmerPosition(sh, at: 9.0 + 1.7))                      // past the card: rest
        XCTAssertNil(Panel.shimmerPosition(sh, at: 9.0 + 4.0))
        XCTAssertEqual(Panel.shimmerPosition(sh, at: 13.5), 0)                      // next sweep
        let xs = stride(from: 9.0, to: 10.6, by: 0.1).compactMap { Panel.shimmerPosition(sh, at: $0) }
        XCTAssertEqual(xs, xs.sorted()) // only left → right
    }

    func testWeatherSymbols() {
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.clear", group: "clear", day: true), "sun.max.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.clear", group: "clear", day: false), "moon.stars.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.overcast", group: "cloudy", day: true), "cloud.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.shower", group: "rain", day: true), "cloud.heavyrain.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.snowfall", group: "snow", day: false), "cloud.snow.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.storm", group: "storm", day: true), "cloud.bolt.rain.fill")
        XCTAssertEqual(Panel.weatherSymbol(key: "weather.new_kind", group: "rain", day: true), "cloud.rain.fill") // by group
        XCTAssertEqual(Panel.weatherSymbol(key: nil, group: nil, day: true), "cloud.fill")
    }

    func testMachineLevels() {
        XCTAssertEqual([5, 74, 75, 89, 90].map(Panel.machineLevel), [.ok, .ok, .warn, .warn, .bad])
    }
}
