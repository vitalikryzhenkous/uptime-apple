import XCTest
@testable import UptimeKit

final class StripTests: XCTestCase {
    func testPulseOnlyWhenItNeedsYou() throws {
        let s = try UptimeJSON.status(from: Data(#"""
        {"api": 1, "claude": {"streams": [
          {"project": "a", "state": "waiting", "ask": "permission"}, {"project": "b", "state": "waiting"},
          {"project": "c", "state": "working"}, {"project": "d", "state": "idle"}, {"project": "e", "state": "open"}]}}
        """#.utf8)).streams
        XCTAssertEqual(s.map(Panel.pulsePeriod), [3.2, 3.2, nil, nil, nil])
        // the strip's colour: red permission, yellow waiting, green working, grey otherwise
        XCTAssertEqual(s.map(Panel.dot), [.bad, .warn, .ok, .muted, .muted])
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
