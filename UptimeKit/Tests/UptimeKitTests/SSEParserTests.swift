import XCTest
@testable import UptimeKit

final class SSEParserTests: XCTestCase {
    private func parse(_ text: String) -> [SSEEvent] {
        var p = SSEParser()
        return Array(text.utf8).compactMap { p.push($0) }
    }

    func testServerFraming() {
        // exactly what server/live.py sends
        let events = parse("event: status\nid: 7\ndata: {\"api\": 1}\n\nevent: ping\ndata: 1793722879\n\n")
        XCTAssertEqual(events, [
            SSEEvent(event: "status", id: "7", data: "{\"api\": 1}"),
            SSEEvent(event: "ping", id: "7", data: "1793722879"),
        ])
    }

    func testCRLFAndMultilineData() {
        let events = parse("event: x\r\ndata: a\r\ndata: b\r\n\r\n")
        XCTAssertEqual(events, [SSEEvent(event: "x", id: nil, data: "a\nb")])
    }

    func testCommentsUnknownFieldsAndDefaultEvent() {
        let events = parse(": keep-alive\nretry: 5000\ndata:no-space\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "message", id: nil, data: "no-space")])
    }

    func testIncompleteEventIsNotDispatched() {
        XCTAssertEqual(parse("event: status\ndata: {}\n"), [])
        XCTAssertEqual(parse("event: lone\n\n"), []) // no data → nothing
    }

    func testUTF8SplitAcrossBytes() {
        let events = parse("data: Миска пуста\n\n")
        XCTAssertEqual(events.first?.data, "Миска пуста")
    }
}
