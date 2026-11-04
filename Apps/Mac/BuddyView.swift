import SwiftUI
import UptimeKit

/// Buddy from /sprites.json: the pose with its overlays. A/B frames (ears, tail, paws, fog) alternate —
/// faster while agents work — and the eyes blink every 5 s, like the board. Still with Reduce Motion.
struct BuddyView: View {
    let sprites: Sprites
    let look: Look
    var pixel: CGFloat = 3
    var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pixels = sprites.pixels(sprites.rows(for: look))
        let size = CGSize(width: CGFloat(sprites.width) * pixel, height: CGFloat(sprites.height) * pixel)
        Group {
            if reduceMotion {
                frame(pixels, phaseB: false, eyesClosed: false)
            } else {
                TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let phaseB = Int(t / (busy ? 0.8 : 2.4)) % 2 == 1
                    let eyesClosed = t.truncatingRemainder(dividingBy: 5) < 0.2
                    frame(pixels, phaseB: phaseB, eyesClosed: eyesClosed)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private func frame(_ pixels: [SpritePixel], phaseB: Bool, eyesClosed: Bool) -> some View {
        Canvas { ctx, _ in
            for p in pixels where p.part.isVisible(phaseB: phaseB, eyesClosed: eyesClosed) {
                let rect = CGRect(x: CGFloat(p.x) * pixel, y: CGFloat(p.y) * pixel, width: pixel, height: pixel)
                ctx.fill(Path(rect), with: .color(Color(p.color)))
            }
        }
    }
}
