import Foundation

extension Panel {
    /// What the popover beside the panel offers under the agent's text.
    public enum PopoverMode: Equatable, Sendable {
        /// The agent waits for you after its turn in tmux: the reply field (and /compact).
        case reply
        /// A dialog is open (a permission or a question): read only — a typed digit would pick an option.
        case readOnly
        /// Just the text (not in tmux, or nothing to answer).
        case text
    }

    public static func popoverMode(_ s: AgentStream) -> PopoverMode {
        if canReply(s) { return .reply }
        if s.stateKind == .waiting && s.inDialog { return .readOnly }
        return .text
    }

    /// The card keeps three lines; longer text, paragraphs or a question's options get "Show all ›".
    public static let cardTextLimit = 140

    public static func showsAll(_ s: AgentStream, text: String) -> Bool {
        text.count > cardTextLimit || text.contains("\n") || !(questionOptions(s).isEmpty)
    }

    /// The question's options (picked in the terminal), only while it asks one.
    public static func questionOptions(_ s: AgentStream) -> [String] {
        guard s.stateKind == .waiting, s.asksQuestion else { return [] }
        return (s.askOptions ?? []).filter { !$0.isEmpty }
    }
}
