import Foundation

/// Buddy in the menu bar tells the state at a glance through his eyes: none lit when nothing runs, green while an
/// agent works, yellow when one waits for you, red and blinking when a dialog (a permission or a question) holds an
/// agent; faded while offline. Only red moves — a steady colour is enough for the rest.
public enum TrayMood: String, Equatable, Sendable {
    case offline, quiet, working, waiting, dialog

    public static func of(_ streams: [AgentStream], offline: Bool) -> TrayMood {
        if offline { return .offline }
        if streams.contains(where: { $0.stateKind == .waiting && $0.inDialog }) { return .dialog }
        if streams.contains(where: { $0.stateKind == .waiting }) { return .waiting }
        if streams.contains(where: { $0.stateKind == .working }) { return .working }
        return .quiet
    }

    /// The eyes' colour, `nil` = holes (the plain template silhouette).
    public var eyes: Level? {
        switch self {
        case .working: return .ok
        case .waiting: return .warn
        case .dialog: return .bad
        case .offline, .quiet: return nil
        }
    }

    public static let blinkPeriod: Double = 1.6
    public static let blinkOff: Double = 0.4 // the last 0.4 s of each period the eyes are dark

    /// Whether the eyes are lit at time `t`: always, except a red blink (none with Reduce Motion).
    public func eyesLit(at t: Double, reduceMotion: Bool) -> Bool {
        guard eyes != nil else { return false }
        guard self == .dialog, !reduceMotion else { return true }
        let local = t.truncatingRemainder(dividingBy: Self.blinkPeriod)
        return local < Self.blinkPeriod - Self.blinkOff
    }
}

extension Sprites {
    /// The eye pixels of a pose (what `silhouette` leaves as holes), to light them in the menu bar.
    public func eyePixels(pose: String = fallbackPose) -> [(x: Int, y: Int)] {
        var out: [(x: Int, y: Int)] = []
        for (y, line) in rows(pose: pose).enumerated() {
            for (x, ch) in line.enumerated() where classes[String(ch)] == "eye" && colors[String(ch)] != nil {
                out.append((x, y))
            }
        }
        return out
    }
}
