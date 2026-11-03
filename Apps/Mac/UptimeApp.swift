import SwiftUI
import UptimeKit

/// Menu-bar app skeleton. The API client, the panel (design "A on Mac"), Buddy and notifications
/// come in the next PRs; for now it proves the target builds and links UptimeKit.
@main
struct UptimeApp: App {
    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            Image(systemName: "cat")
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uptime")
                .font(.headline)
            Text("API v\(UptimeJSON.supportedAPI) · not connected yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .panelBackground()
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
