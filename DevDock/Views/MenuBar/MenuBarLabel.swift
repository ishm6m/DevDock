import SwiftUI

/// The status-item content shown in the macOS menu bar.
///
/// Uses a monochrome SF Symbol (rendered as a template image by `MenuBarExtra`, so it
/// tracks the menu bar's light/dark tint like a first-party item) plus the active
/// server count. The glyph fills in when servers are running and hollows out when idle.
///
/// The view model is observed *here*, inside the label, rather than at the App/Scene
/// level: the count updates the status item in place, without rebuilding the
/// `MenuBarExtra` scene (which would dismiss the open panel). See `DevDockApp`.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: MenuBarViewModel

    private var count: Int { viewModel.activeServerCount }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                .font(.system(size: 13))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(count == 0 ? "DevDock, no servers running" : "DevDock, \(count) servers running")
    }
}
