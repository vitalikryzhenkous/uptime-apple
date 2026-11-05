import AppKit
import UptimeKit
import UserNotifications

/// A macOS notification for each open permission request (`Panel.permissionNotices`), with "Deny" and "Open".
/// "Allow once" is never in a notification: only in the popover, beside the whole command. A notification is taken
/// back once its request is answered anywhere or expires. Asks macOS for permission at the first request, not at launch.
@MainActor
final class PermissionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "uptime.permission"
    static let denyAction = "deny"
    static let openAction = "open"

    private let store: LiveStore
    private let assets: AssetStore
    /// Open the panel at this card and its popover (the hotkey's path).
    private let open: @MainActor (String) -> Void
    /// Whether the panel is on screen: then a new request goes only to Notification Centre, without a banner.
    private let panelOpen: @MainActor () -> Bool
    private var shown: Set<String> = []
    private var authorized: Bool?
    private var categoryTitles: [String] = []
    private var center: UNUserNotificationCenter { .current() }

    init(store: LiveStore, assets: AssetStore,
         open: @escaping @MainActor (String) -> Void, panelOpen: @escaping @MainActor () -> Bool) {
        self.store = store
        self.assets = assets
        self.open = open
        self.panelOpen = panelOpen
    }

    func start() {
        center.delegate = self
        watch()
    }

    private func watch() {
        withObservationTracking {
            _ = store.status
            _ = assets.strings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.update()
                self.watch()
            }
        }
    }

    /// Post the new requests, take back the closed ones. Also after the Settings switch changes.
    func update() {
        guard Prefs.notifyPermissions else {
            withdraw(Array(shown))
            shown = []
            return
        }
        let s = assets.strings
        let changes = Panel.permissionNotices(store.status, shown: shown, now: store.serverNow(), s)
        withdraw(changes.withdraw)
        shown.subtract(changes.withdraw)
        guard !changes.post.isEmpty else { return }
        shown.formUnion(changes.post.map(\.id))
        registerCategory(s)
        Task {
            guard await authorize() else { return }
            for n in changes.post { post(n) }
        }
    }

    private func withdraw(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func authorize() async -> Bool {
        if let authorized { return authorized }
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorized = ok
        return ok
    }

    /// The buttons' titles follow the board's language.
    private func registerCategory(_ s: Strings) {
        let titles = [s.tr("app.perm.deny", fallback: "Deny"), s.tr("app.perm.open", fallback: "Open")]
        guard titles != categoryTitles else { return }
        categoryTitles = titles
        let deny = UNNotificationAction(identifier: Self.denyAction, title: titles[0], options: [.destructive])
        let open = UNNotificationAction(identifier: Self.openAction, title: titles[1], options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [deny, open], intentIdentifiers: []),
        ])
    }

    private func post(_ n: PermissionNotice) {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = n.streamID
        content.userInfo = ["request": n.id, "stream": n.streamID]
        center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: nil))
    }

    // MARK: answers

    private func answer(action: String, request: String, stream: String) {
        switch action {
        case Self.denyAction: deny(request)
        case Self.openAction, UNNotificationDefaultActionIdentifier: open(stream)
        default: break // dismissed
        }
    }

    /// The same call as the card's "Deny"; the outcome comes back as a short notification.
    private func deny(_ request: String) {
        let s = assets.strings
        Task {
            let text: String
            if let client = Prefs.makeClient() {
                switch try? await client.decide(.deny, request: request) {
                case .done: text = s.tr("app.perm.denied", fallback: "Denied")
                case .refused(let code): text = Panel.decisionErrorText(code, s)
                case nil: text = Panel.decisionErrorText("network", s)
                }
            } else {
                text = Panel.decisionErrorText("network", s)
            }
            let content = UNMutableNotificationContent()
            content.title = text
            try? await center.add(UNNotificationRequest(identifier: "\(request).answer", content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let request = info["request"] as? String, let stream = info["stream"] as? String else { return }
        let action = response.actionIdentifier
        await MainActor.run { answer(action: action, request: request, stream: stream) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let quiet = await MainActor.run { panelOpen() }
        return quiet ? [.list] : [.banner, .list, .sound]
    }
}
