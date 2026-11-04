import Foundation

extension Panel {
    /// Where the global hotkey (⌥⌘U) jumps: an open dialog first (a permission or a question holds the agent),
    /// then the session waiting longest. `nil` = nobody waits — the panel just opens.
    public static func jumpTarget(_ streams: [AgentStream]) -> AgentStream? {
        let rank = { (s: AgentStream) -> (Int, Double) in (s.inDialog ? 0 : 1, s.since ?? .infinity) }
        return streams.filter { $0.stateKind == .waiting }.min { rank($0) < rank($1) }
    }
}
