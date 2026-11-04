import AppKit
import Carbon.HIToolbox
import Observation
import UptimeKit

/// A system-wide shortcut through Carbon's RegisterEventHotKey: works in the App Store sandbox and needs no
/// Accessibility permission (it only hears its own combination, not every key).
@MainActor
final class HotKey {
    nonisolated(unsafe) private var ref: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private let action: () -> Void

    /// ⌥⌘U — U for Uptime.
    static let defaultKey = (code: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey | optionKey))

    init?(code: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            guard let user else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(user).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() } // Carbon delivers application events on the main thread
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x5550_5442), id: 1) // "UPTB"
        guard RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

/// What the hotkey asked the panel to do: the card to jump to, taken once by whichever view shows it
/// (the reply field gets the focus; a dialog or a card without a reply field opens its popover).
@MainActor
@Observable
final class JumpRequest {
    private(set) var nonce = 0
    private var pending: String?
    var panelOpen = false

    func request(_ streamID: String?) {
        pending = streamID
        nonce += 1
    }

    /// True once for the card the hotkey points at.
    func take(_ streamID: String) -> Bool {
        guard pending == streamID else { return false }
        pending = nil
        return true
    }
}

/// MenuBarExtra has no API to open its window, so the hotkey clicks the menu-bar button the way a person would
/// (the approach of the MenuBarExtraAccess library). If a future macOS changes the window, this finds nothing
/// and the hotkey does nothing — it never breaks the panel itself.
enum StatusItemButton {
    @MainActor
    static func click() -> Bool {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBarWindow") {
            if let button = firstButton(in: window.contentView) {
                button.performClick(nil)
                return true
            }
        }
        return false
    }

    @MainActor
    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews {
            if let button = firstButton(in: sub) { return button }
        }
        return nil
    }
}
