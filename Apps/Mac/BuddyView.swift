import SwiftUI
import UptimeKit

/// Buddy from /sprites.json: the pose with its overlays, A frame, eyes open. Animation comes with the panel (PR 4b).
struct BuddyView: View {
    let sprites: Sprites
    let look: Look
    var pixel: CGFloat = 4

    var body: some View {
        let pixels = sprites.pixels(sprites.rows(for: look))
        Canvas { ctx, _ in
            for p in pixels where p.part.isVisible(phaseB: false) {
                let rect = CGRect(x: CGFloat(p.x) * pixel, y: CGFloat(p.y) * pixel, width: pixel, height: pixel)
                ctx.fill(Path(rect), with: .color(Color(red: p.color.r, green: p.color.g, blue: p.color.b)))
            }
        }
        .frame(width: CGFloat(sprites.width) * pixel, height: CGFloat(sprites.height) * pixel)
        .accessibilityHidden(true)
    }
}
