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
                .environment(app.jump)
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
    /// The hotkey's "go to this card" for the panel.
    let jump = JumpRequest()
    private var assetsBuild: String?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        hotKey = HotKey(code: HotKey.defaultKey.code, modifiers: HotKey.defaultKey.modifiers) { [weak self] in
            self?.hotKeyPressed()
        }
        watchBuild()
        // the stream is dead after sleep; reconnect at once instead of waiting for the idle timeout
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.start() }
        }
    }

    /// ⌥⌘U: open the panel (if closed) at the card that needs you most — `Panel.jumpTarget`.
    private func hotKeyPressed() {
        jump.request(Panel.jumpTarget(store.status?.streams ?? [])?.id)
        NSApp.activate()
        if !jump.panelOpen { _ = StatusItemButton.click() }
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

/// Buddy in the menu bar (his silhouette from /sprites.json), faded while offline; his eyes tell the state
/// (`TrayMood`): green working, yellow waiting for you, red and blinking on a permission or a question.
/// The number of sessions waiting for you next to him, with "!" when a dialog is open.
struct MenuBarIcon: View {
    let store: LiveStore
    let sprites: Sprites?
    @State private var now = Date()
    private let blink = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let streams = store.status?.streams ?? []
        let offline = Panel.showsOffline(store.connection, offlineSince: store.offlineSince,
                                         hasData: store.status != nil, now: Date())
        let waiting = Panel.waitingCount(streams)
        let ask = streams.contains { $0.inDialog }
        let mood = TrayMood.of(streams, offline: offline)
        let lit = mood.eyesLit(at: now.timeIntervalSinceReferenceDate,
                               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        HStack(spacing: 3) {
            if let sprites {
                Image(nsImage: BuddyGlyph.image(sprites, alpha: offline ? 0.4 : 1, eyes: lit ? mood.eyes : nil))
                    .accessibilityLabel("Uptime: \(mood.rawValue)")
            } else {
                Image(systemName: "cat")
            }
            if !offline, waiting > 0 {
                Text(ask ? "\(waiting)!" : "\(waiting)").monospacedDigit()
            }
        }
        .onReceive(blink) { t in if mood == .dialog { now = t } } // redraw only while red blinks
    }
}

enum BuddyGlyph {
    /// 1 pt per sprite pixel: 14×14 pt, crisp at 2× (each pixel is 2×2 device pixels).
    /// No eyes: a template image (the menu bar colours it). Lit eyes need colour, so then the body is drawn in
    /// the label colour, resolved when the menu bar draws it (light or dark menu bar).
    static func image(_ sprites: Sprites, alpha: CGFloat, eyes: Level? = nil) -> NSImage {
        let pixels = sprites.silhouette()
        let eyePixels = eyes == nil ? [] : sprites.eyePixels()
        let eyeColor: NSColor? = switch eyes {
        case .ok: .systemGreen
        case .warn: .systemYellow
        case .bad: .systemRed
        case .muted, nil: nil
        }
        let image = NSImage(size: NSSize(width: sprites.width, height: sprites.height), flipped: true) { _ in
            (eyeColor == nil ? NSColor.black : NSColor.labelColor).withAlphaComponent(alpha).setFill()
            for p in pixels { NSRect(x: p.x, y: p.y, width: 1, height: 1).fill() }
            if let eyeColor {
                eyeColor.setFill()
                for p in eyePixels { NSRect(x: p.x, y: p.y, width: 1, height: 1).fill() }
            }
            return true
        }
        image.isTemplate = eyeColor == nil
        image.accessibilityDescription = "Uptime"
        return image
    }
}
