import SwiftUI
import UptimeKit

/// The board's themes from the "A on Mac" mock: Dracula (dark) and Alucard (light), WCAG AA on the card colour.
struct Theme {
    let glass: Color, card: Color, line: Color, fg: Color, g2: Color
    let y: Color, gr: Color, b: Color, r: Color, on: Color

    static let dark = Theme(
        glass: Color(hex: "#21222C", opacity: 0.92), card: Color(hex: "#44475A", opacity: 0.45), line: Color(hex: "#44475A"),
        fg: Color(hex: "#F8F8F2"), g2: Color(hex: "#C5C8D6"), y: Color(hex: "#F1FA8C"), gr: Color(hex: "#50FA7B"),
        b: Color(hex: "#BD93F9"), r: Color(hex: "#FF6E6E"), on: Color(hex: "#21222C"))

    static let light = Theme(
        glass: Color(hex: "#FFFBEB", opacity: 0.94), card: Color(hex: "#CFCFDE", opacity: 0.45), line: Color(hex: "#CFCFDE"),
        fg: Color(hex: "#1F1F1F"), g2: Color(hex: "#3C3A2E"), y: Color(hex: "#6E5A0C"), gr: Color(hex: "#14710A"),
        b: Color(hex: "#644AC9"), r: Color(hex: "#B8321F"), on: Color(hex: "#FFFBEB"))

    static func of(_ scheme: ColorScheme) -> Theme { scheme == .dark ? dark : light }

    func color(_ level: Level) -> Color {
        switch level {
        case .ok: return gr
        case .warn: return y
        case .bad: return r
        case .muted: return g2
        }
    }

    func color(_ check: CheckState?) -> Color {
        switch check {
        case .ok?: return gr
        case .fail?: return r
        case .run?: return y
        case nil: return g2
        }
    }
}

extension Color {
    init(hex: String, opacity: Double = 1) {
        let c = RGB(hex: hex) ?? RGB(r: 1, g: 0, b: 1)
        self.init(red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }

    init(_ rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension View {
    /// Liquid Glass tinted with the theme on macOS 26; the theme's glass over `.ultraThinMaterial` before.
    @ViewBuilder
    func panelBackground(_ t: Theme) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(t.glass.opacity(0.55)), in: .rect(cornerRadius: 18))
        } else {
            self.background(t.glass.opacity(0.8), in: .rect(cornerRadius: 18))
        }
        #else
        self.background(t.glass.opacity(0.8), in: .rect(cornerRadius: 18))
        #endif
    }
}
