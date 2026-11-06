import AppKit
import SwiftUI
import UptimeKit

/// A command to paste into Terminal, with a Copy button that says "Copied" until the command changes.
struct CopyLine: View {
    let text: String
    let strings: Strings
    @State private var copied = false

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
            Button(copied ? strings.tr("app.onb.copied", fallback: "Copied") : strings.tr("app.onb.copy", fallback: "Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
            .disabled(text.isEmpty)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: text) { copied = false }
    }
}
