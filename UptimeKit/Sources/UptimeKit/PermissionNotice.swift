import Foundation

/// A macOS notification for an open permission request. It offers "Deny" and "Open" (the card's popover) only:
/// "Allow once" stays in the popover, beside the whole command.
public struct PermissionNotice: Equatable, Sendable {
    /// The request's id, also the notification's identifier.
    public let id: String
    /// The card to open (`AgentStream.id`).
    public let streamID: String
    public let title: String
    public let body: String
}

extension Panel {
    /// What to show and what to take back since the last update.
    public struct NoticeChanges: Equatable, Sendable {
        public let post: [PermissionNotice]
        /// Ids of shown notifications whose request is gone (answered anywhere, expired, or the opt-in is off).
        public let withdraw: [String]
    }

    /// The command in a notification: macOS cuts long bodies anyway, the whole one is in the popover.
    public static let noticeBodyLimit = 180

    /// One notice per card with an open request (the one the card shows), each request once. Without a status
    /// (offline) nothing changes: the requests may still be open.
    public static func permissionNotices(_ st: Status?, shown: Set<String>, now: Double, _ t: Strings) -> NoticeChanges {
        guard let st else { return NoticeChanges(post: [], withdraw: []) }
        var open: [PermissionNotice] = []
        for s in st.streams {
            guard let r = permission(for: s, in: st.permissions, now: now), !open.contains(where: { $0.id == r.id })
            else { continue }
            open.append(notice(r, s: s, t))
        }
        let ids = Set(open.map(\.id))
        return NoticeChanges(post: open.filter { !shown.contains($0.id) }, withdraw: shown.subtracting(ids).sorted())
    }

    static func notice(_ r: PermissionRequest, s: AgentStream, _ t: Strings) -> PermissionNotice {
        let title = t.tr("app.notify.perm.title", ["project": .string(s.project)],
                         fallback: "\(s.project) asks for permission")
        var body = permissionText(r, s: s, t)
        if body.count > noticeBodyLimit { body = String(body.prefix(noticeBodyLimit - 1)) + "…" }
        if let why = denyOnlyText(r, t) { body += "\n" + why }
        return PermissionNotice(id: r.id, streamID: s.id, title: title, body: body)
    }
}
