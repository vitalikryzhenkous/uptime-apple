import SwiftUI
import UptimeKit

/// Menu-bar app: the panel (design "A on Mac") and Settings. Notifications come next.
@main
struct UptimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(app.store)
                .environment(app.assets)
        } label: {
            MenuBarIcon(connection: app.store.connection, streams: app.store.status?.streams ?? [])
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(refreshAssets: app.refreshAssets)
                .environment(app.store)
                .environment(app.assets)
        }
    }
}

/// Owns the stores, so the app connects at launch — not only when the panel is first opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LiveStore(makeSource: Prefs.makeSource)
    /// Strings and sprites; drawn from the disk cache until the first refresh.
    let assets = AssetStore(cache: .standard())
    private var assetsBuild: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        watchBuild()
        // the stream is dead after sleep; reconnect at once instead of waiting for the idle timeout
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.start() }
        }
    }

    /// Fetch locales, sprites and ext again (language change, new board build).
    func refreshAssets() {
        guard let client = Prefs.makeClient() else { return }
        let assets = self.assets
        Task { await assets.refresh(from: client, preferred: Prefs.lang) }
    }

    /// Refresh assets on the first status and whenever the board's build id changes (a deploy may change texts or art).
    private func watchBuild() {
        withObservationTracking {
            _ = store.status?.build
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let build = self.store.status?.build, build != self.assetsBuild {
                    self.assetsBuild = build
                    self.refreshAssets()
                }
                self.watchBuild()
            }
        }
    }
}

/// The cat in the menu bar; with the number of sessions waiting for you next to it.
struct MenuBarIcon: View {
    let connection: ConnectionState
    let streams: [AgentStream]

    var body: some View {
        let waiting = Panel.waitingCount(streams)
        let ask = streams.contains { $0.asksPermission }
        HStack(spacing: 2) {
            Image(systemName: connection != .live ? "cat" : ask ? "exclamationmark.bubble.fill" : "cat.fill")
            if connection == .live, waiting > 0 {
                Text("\(waiting)").monospacedDigit()
            }
        }
    }
}
