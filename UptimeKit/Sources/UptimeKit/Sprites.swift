import Foundation

/// Buddy's pixel art (`GET /sprites.json`), shared with the board. A pose is a list of rows, one char per pixel;
/// overlays are laid on top (`.` = transparent); `colors` maps a char to hex, `classes` to an animation frame class.
public struct Sprites: Decodable, Sendable, Equatable {
    public let size: [Int]
    public let colors: [String: String]
    public let classes: [String: String]
    public let poses: [String: [String]]
    public let overlays: [String: [String]]
    public let marks: [String: [String]]

    public var width: Int { size.first ?? 14 }
    public var height: Int { size.count > 1 ? size[1] : 14 }

    public static let fallbackPose = "sit"

    public static func decode(_ data: Data) throws -> Sprites {
        try JSONDecoder().decode(Sprites.self, from: data)
    }

    /// The pose with each overlay laid on top, exactly like layered() in board.js. Unknown names are skipped;
    /// an unknown pose falls back to `sit`.
    public func rows(pose: String, overlays names: [String] = []) -> [String] {
        var out = (poses[pose] ?? poses[Self.fallbackPose] ?? []).map { Array($0) }
        for name in names {
            guard let ov = overlays[name] else { continue }
            for (y, line) in ov.enumerated() where y < out.count {
                for (x, ch) in line.enumerated() where ch != "." {
                    if x < out[y].count { out[y][x] = ch } else if x == out[y].count { out[y].append(ch) }
                }
            }
        }
        return out.map { String($0) }
    }

    public func rows(for look: Look) -> [String] {
        rows(pose: look.pose, overlays: look.overlays ?? [])
    }

    /// Every coloured pixel of `rows`; chars without a colour are transparent.
    public func pixels(_ rows: [String]) -> [SpritePixel] {
        var out: [SpritePixel] = []
        for (y, line) in rows.enumerated() {
            for (x, ch) in line.enumerated() {
                let c = String(ch)
                guard let hex = colors[c], let rgb = RGB(hex: hex) else { continue }
                out.append(SpritePixel(x: x, y: y, color: rgb, part: SpritePart(classes[c])))
            }
        }
        return out
    }
}

/// What a pixel belongs to for animation. The board shows A frames and hides B frames at rest;
/// animations swap them; eyes blink.
public enum SpritePart: Sendable, Equatable {
    case body, eye, frameA, frameB

    init(_ cls: String?) {
        switch cls {
        case "eye": self = .eye
        case let c? where c.hasSuffix("A"): self = .frameA
        case let c? where c.hasSuffix("B"): self = .frameB
        default: self = .body
        }
    }

    /// Visible in this animation `phase` (false = A, true = B), with eyes open or closed.
    public func isVisible(phaseB: Bool, eyesClosed: Bool = false) -> Bool {
        switch self {
        case .body: return true
        case .eye: return !eyesClosed
        case .frameA: return !phaseB
        case .frameB: return phaseB
        }
    }
}

public struct SpritePixel: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let color: RGB
    public let part: SpritePart
}

/// A colour from `#RRGGBB`, components 0…1.
public struct RGB: Sendable, Equatable {
    public let r: Double, g: Double, b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }
}
