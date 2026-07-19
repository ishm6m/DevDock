import AppKit
import SwiftUI

/// Presents the first-run welcome window and owns its lifecycle.
///
/// DevDock is an `LSUIElement` accessory app: launching it produces no dock icon and no
/// window, only a small menu-bar item. On first run that's disorienting — a new user
/// can't tell the app launched or where it went. This controller shows a one-time
/// welcome that proves DevDock is running, points at the menu-bar icon, states the
/// safety model, and primes notification permission *before* the system prompt fires.
///
/// It is deliberately decoupled from the SwiftUI scene graph. Driving presentation from
/// observed App-level state would re-evaluate `DevDockApp.body`, rebuild the
/// `MenuBarExtra`, and dismiss the open panel out from under the user (the same reason
/// the view model is a plain `let`). So the window is created imperatively here and
/// never touches the App scene.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {

    private let state: OnboardingState
    private let onEnableNotifications: () -> Void
    private var window: NSWindow?

    /// - Parameters:
    ///   - state: the first-run flag store (injectable for testing).
    ///   - onEnableNotifications: invoked when the user opts into notifications, so the
    ///     real authorization prompt fires from a deliberate tap rather than at launch.
    init(state: OnboardingState, onEnableNotifications: @escaping () -> Void) {
        self.state = state
        self.onEnableNotifications = onEnableNotifications
    }

    /// Shows the welcome window if the user hasn't completed onboarding yet.
    ///
    /// - Returns: `true` if it presented. The caller uses this to suppress the
    ///   launch-time notification request on a first run — onboarding owns that prompt.
    @discardableResult
    func presentIfNeeded() -> Bool {
        guard state.shouldShowOnboarding, window == nil else { return false }
        present()
        return true
    }

    private func present() {
        let view = OnboardingView(
            onEnableNotifications: { [weak self] in self?.onEnableNotifications() },
            onFinish: { [weak self] in self?.finish() }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to DevDock"
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        // An accessory app doesn't come forward on its own; activate so the welcome
        // takes focus and the user actually sees it.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Completes onboarding from a button tap and closes the window.
    private func finish() {
        state.markCompleted()
        window?.close()
    }

    /// Any close path — a footer button or the red traffic-light — completes
    /// onboarding, so the welcome never reappears. `markCompleted` is idempotent, so
    /// the button path routing through `close()` to here is harmless.
    func windowWillClose(_ notification: Notification) {
        state.markCompleted()
        window = nil
    }
}
