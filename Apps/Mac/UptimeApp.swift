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
            MenuBarIcon(store: app.store, sprites: app.assets.sprites)
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

/// Buddy in the menu bar (his silhouette from /sprites.json, a template image so it follows the menu bar's colour),
/// faded while offline; the number of sessions waiting for you next to him, with "!" when one asks for a permission.
struct MenuBarIcon: View {
    let store: LiveStore
    let sprites: Sprites?

    var body: some View {
        let streams = store.status?.streams ?? []
        let offline = Panel.showsOffline(store.connection, offlineSince: store.offlineSince,
                                         hasData: store.status != nil, now: Date())
        let waiting = Panel.waitingCount(streams)
        let ask = streams.contains { $0.inDialog }
        HStack(spacing: 3) {
            if let sprites {
                Image(nsImage: BuddyGlyph.image(sprites, alpha: offline ? 0.4 : 1))
            } else {
                Image(systemName: "cat")
            }
            if !offline, waiting > 0 {
                Text(ask ? "\(waiting)!" : "\(waiting)").monospacedDigit()
            }
        }
    }
}

enum BuddyGlyph {
    /// 1 pt per sprite pixel: 14×14 pt, crisp at 2× (each pixel is 2×2 device pixels).
    static func image(_ sprites: Sprites, alpha: CGFloat) -> NSImage {
        let pixels = sprites.silhouette()
        let image = NSImage(size: NSSize(width: sprites.width, height: sprites.height), flipped: true) { _ in
            NSColor.black.withAlphaComponent(alpha).setFill()
            for p in pixels { NSRect(x: p.x, y: p.y, width: 1, height: 1).fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Uptime"
        return image
    }
}
