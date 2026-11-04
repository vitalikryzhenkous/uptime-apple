import XCTest
@testable import UptimeKit

final class SpritesTests: XCTestCase {
    private func sprites() throws -> Sprites {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sprites-mini", withExtension: "json", subdirectory: "Fixtures"))
        return try Sprites.decode(Data(contentsOf: url))
    }

    func testDecode() throws {
        let s = try sprites()
        XCTAssertEqual(s.width, 4)
        XCTAssertEqual(s.height, 3)
        XCTAssertEqual(s.marks["heart"]?.count, 2)
    }

    func testLayeringLikeBoard() throws {
        let s = try sprites()
        XCTAssertEqual(s.rows(pose: "sit"), [".oo.", "oeeo", "ootT"])
        // overlay chars replace, '.' keeps the pose
        XCTAssertEqual(s.rows(pose: "sit", overlays: ["hat"]), ["hhhh", "oeeo", "ootT"])
        XCTAssertEqual(s.rows(pose: "sit", overlays: ["hat", "dot"]), ["hhhh", "oxeo", "ootT"])
        // unknown overlay skipped, unknown pose → sit
        XCTAssertEqual(s.rows(pose: "flying", overlays: ["nope"]), [".oo.", "oeeo", "ootT"])
    }

    func testRowsForLook() throws {
        let s = try sprites()
        let status = try UptimeJSON.status(from: Data(#"""
        {"api": 1, "nikolai": [{"id": "m", "kind": "mood",
          "look": {"pose": "lie", "overlays": ["hat"], "scene": "dark", "mark": null, "anim": null, "glow": false}}]}
        """#.utf8))
        XCTAssertEqual(s.rows(for: try XCTUnwrap(status.cat?.look)), ["hhhh", "oooo", "oeot"])
    }

    func testPixelsAndParts() throws {
        let s = try sprites()
        let px = s.pixels(s.rows(pose: "sit", overlays: ["dot"]))
        // 'x' has an invalid colour and '.' none → skipped; 12 cells − 2 dots − 1 'x' = 9
        XCTAssertEqual(px.count, 9)
        XCTAssertEqual(px.first, SpritePixel(x: 1, y: 0, color: RGB(hex: "#45475E")!, part: .body))
        XCTAssertEqual(px.filter { $0.part == .eye }.count, 1)
        XCTAssertEqual(px.first { $0.x == 2 && $0.y == 2 }?.part, .frameA)
        XCTAssertEqual(px.first { $0.x == 3 && $0.y == 2 }?.part, .frameB)
    }

    func testVisibility() {
        XCTAssertTrue(SpritePart.body.isVisible(phaseB: true, eyesClosed: true))
        XCTAssertTrue(SpritePart.frameA.isVisible(phaseB: false))
        XCTAssertFalse(SpritePart.frameB.isVisible(phaseB: false)) // B frames hidden at rest, like the board
        XCTAssertTrue(SpritePart.frameB.isVisible(phaseB: true))
        XCTAssertFalse(SpritePart.eye.isVisible(phaseB: false, eyesClosed: true))
        XCTAssertEqual(SpritePart("fogB"), .frameB)
        XCTAssertEqual(SpritePart(nil), .body)
    }

    func testRGB() {
        XCTAssertEqual(RGB(hex: "#FF0080"), RGB(r: 1, g: 0, b: 128.0 / 255))
        XCTAssertEqual(RGB(hex: "00FF00"), RGB(r: 0, g: 1, b: 0))
        XCTAssertNil(RGB(hex: "#FFF"))
        XCTAssertNil(RGB(hex: "nothex"))
    }
}
