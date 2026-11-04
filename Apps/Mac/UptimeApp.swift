import SwiftUI
import UptimeKit

/// Menu-bar app. The full panel (design "A on Mac") and notifications come in the next PRs.
@main
struct UptimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(app.store)
                .environment(app.assets)
        } label: {
            MenuBarIcon(connection: app.store.connection)
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

struct MenuBarIcon: View {
    let connection: ConnectionState

    var body: some View {
        Image(systemName: connection == .live ? "cat.fill" : "cat")
    }
}

struct PanelView: View {
    @Environment(LiveStore.self) private var store
    @Environment(AssetStore.self) private var assets

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uptime").font(.headline)
            ConnectionLine(connection: store.connection, lastUpdate: store.lastUpdate)
            if let s = store.status {
                Text("Agents: \(s.streams.count)").font(.callout)
                if let limits = s.claude?.limits {
                    Text("5h \(percent(limits.h5?.pct)) · week \(percent(limits.d7?.pct))")
                        .font(.callout.monospacedDigit())
                }
                if let cat = s.cat {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        if let sprites = assets.sprites, let look = cat.look {
                            BuddyView(sprites: sprites, look: look)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assets.ext?.persona?.name ?? s.persona?.name ?? "Buddy").font(.caption.bold())
                            Text(assets.strings.text(for: cat))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .panelBackground()
    }

    private func percent(_ v: Double?) -> String {
        v.map { "\(Int($0.rounded())) %" } ?? "—"
    }
}

struct ConnectionLine: View {
    let connection: ConnectionState
    let lastUpdate: Date?

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(connection == .live ? Color.secondary : Color.orange)
    }

    // English placeholders until the app's own strings join the board's locales (PR 4b).
    private var text: String {
        switch connection {
        case .idle: return "Not started"
        case .noToken: return "No token — open Settings"
        case .connecting: return "Connecting…"
        case .live:
            if let t = lastUpdate { return "Live · updated \(t.formatted(date: .omitted, time: .shortened))" }
            return "Live"
        case .retrying(let s, let reason): return "Offline (\(reason)) · retry in \(s) s"
        case .unauthorized: return "Wrong token (401) — check Settings"
        case .notConfigured: return "Server has no UPTIME_API_TOKEN (503)"
        case .unsupportedAPI(let v): return "Server API v\(v) is newer — update the app"
        }
    }

    private var icon: String {
        switch connection {
        case .live: return "dot.radiowaves.left.and.right"
        case .connecting, .idle: return "ellipsis"
        default: return "exclamationmark.triangle"
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, `.ultraThinMaterial` before.
    @ViewBuilder
    func panelBackground() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        }
        #else
        self.background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        #endif
    }
}
