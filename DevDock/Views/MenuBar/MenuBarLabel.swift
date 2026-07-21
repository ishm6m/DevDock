import SwiftUI
import AppKit

/// The status-item content shown in the macOS menu bar.
///
/// Uses a monochrome, runtime-drawn rocket glyph — the DevDock mark — as a `template`
/// image, so `MenuBarExtra` tints and inverts it to match the menu bar's light/dark
/// appearance like a first-party item. The rocket is solid when servers are running and
/// dimmed when idle, and the active count sits beside it.
///
/// The view model is observed *here*, inside the label, rather than at the App/Scene
/// level: the count updates the status item in place, without rebuilding the
/// `MenuBarExtra` scene (which would dismiss the open panel). See `DevDockApp`.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: MenuBarViewModel

    private var count: Int { viewModel.activeServerCount }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.rocketGlyph(active: count > 0))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(count == 0 ? "DevDock, no servers running" : "DevDock, \(count) servers running")
    }

    /// The rocket silhouette, drawn as a `template` `NSImage` so the menu bar tints it.
    /// A full-alpha fill reads as "active"; a half-alpha fill dims it for the idle state —
    /// the same crisp shape either way, which stays legible at 16px where a stroked
    /// outline would smear. The porthole is punched with an even-odd fill.
    /// Built once per state and reused. The glyph never varies, but this is re-read on
    /// every label render — i.e. on every discovery tick for the life of the app — so
    /// rebuilding the bezier paths each time was pure waste.
    static func rocketGlyph(active: Bool) -> NSImage { active ? activeGlyph : idleGlyph }

    private static let activeGlyph = drawRocket(active: true)
    private static let idleGlyph = drawRocket(active: false)

    private static func drawRocket(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 16), flipped: false) { rect in
            func p(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
            }

            let body = NSBezierPath()
            body.move(to: p(0.50, 0.98))
            body.curve(to: p(0.72, 0.42), controlPoint1: p(0.70, 0.86), controlPoint2: p(0.75, 0.60))
            body.curve(to: p(0.66, 0.24), controlPoint1: p(0.71, 0.34), controlPoint2: p(0.69, 0.28))
            body.curve(to: p(0.34, 0.24), controlPoint1: p(0.60, 0.18), controlPoint2: p(0.40, 0.18))
            body.curve(to: p(0.28, 0.42), controlPoint1: p(0.31, 0.28), controlPoint2: p(0.29, 0.34))
            body.curve(to: p(0.50, 0.98), controlPoint1: p(0.25, 0.60), controlPoint2: p(0.30, 0.86))
            body.close()

            let extras = NSBezierPath()   // two fins + a nozzle
            extras.move(to: p(0.66, 0.40)); extras.line(to: p(0.90, 0.15)); extras.line(to: p(0.66, 0.23)); extras.close()
            extras.move(to: p(0.34, 0.40)); extras.line(to: p(0.10, 0.15)); extras.line(to: p(0.34, 0.23)); extras.close()
            extras.move(to: p(0.44, 0.24)); extras.line(to: p(0.46, 0.10)); extras.line(to: p(0.54, 0.10)); extras.line(to: p(0.56, 0.24)); extras.close()

            let portR = 0.12 * rect.width
            let portC = p(0.50, 0.60)
            let port = NSBezierPath(ovalIn: NSRect(x: portC.x - portR, y: portC.y - portR, width: portR * 2, height: portR * 2))

            NSColor.black.withAlphaComponent(active ? 1.0 : 0.5).setFill()
            extras.fill()
            let holed = NSBezierPath()
            holed.append(body)
            holed.append(port)
            holed.windingRule = .evenOdd
            holed.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
