import Foundation
import AppKit
import Sparkle

/// Abstraction over the software-update mechanism.
///
/// DevDock ships outside the Mac App Store (it can't be sandboxed — see the README), so
/// it needs its own update path: without one a downloaded build can never receive a fix.
/// Sparkle is the standard answer for a Developer ID app. The UI depends only on this
/// protocol, never on Sparkle directly, matching the rest of the codebase (services are
/// protocols constructed once in `AppEnvironment`).
@MainActor
protocol UpdateChecking: AnyObject {
    /// Whether this build can actually check for updates.
    ///
    /// False for builds from source, where `SUFeedURL`/`SUPublicEDKey` are still the
    /// placeholders committed to the tree. The UI uses this to hide update controls
    /// rather than offer a button that can't work.
    var supportsUpdates: Bool { get }

    /// Whether Sparkle checks for updates automatically in the background. Backed by
    /// Sparkle's own persisted setting — deliberately *not* mirrored into `Preferences`,
    /// so there's a single source of truth.
    var automaticallyChecksForUpdates: Bool { get set }

    /// Starts the background updater. Called once, at `applicationDidFinishLaunching`,
    /// alongside the other runtime services — never during `AppEnvironment` construction.
    func startUpdater()

    /// Runs a user-initiated update check, bringing Sparkle's window to the front.
    func checkForUpdates()
}

/// `Sparkle`-backed `UpdateChecking`.
///
/// Two things here are deliberate:
///
/// 1. **It stays dormant unless real credentials are configured.** `SPUStandardUpdaterController`
///    validates its security configuration when the updater starts and, if the feed or
///    public key is missing/placeholder, shows a modal "improperly configured" alert.
///    That would fire on every build-from-source. So `startUpdater()` is a no-op until a
///    maintainer replaces the `SUFeedURL`/`SUPublicEDKey` placeholders at release time.
///
/// 2. **Activation before a check.** DevDock is an `LSUIElement` accessory app; it doesn't
///    come forward on its own, so a manual check activates first or Sparkle's dialog would
///    appear behind everything (the same fix the onboarding window uses).
@MainActor
final class SparkleUpdater: UpdateChecking {

    private let controller: SPUStandardUpdaterController
    private var started = false

    let supportsUpdates: Bool

    init() {
        supportsUpdates = Self.isConfigured()
        // startingUpdater: false — creating the controller must not validate config or
        // schedule checks yet. We start it explicitly from the app delegate.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func startUpdater() {
        guard supportsUpdates else {
            Log.app.info("Sparkle: no release feed/key configured; auto-update is disabled in this build.")
            return
        }
        controller.startUpdater()
        started = true
    }

    func checkForUpdates() {
        guard supportsUpdates, started else { return }
        // An accessory app must activate or Sparkle's update window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether Info.plist carries a real signing key and feed rather than the placeholders
    /// committed to the source tree. Keeps builds-from-source free of Sparkle's config alert.
    private static func isConfigured() -> Bool {
        let info = Bundle.main.infoDictionary
        let key = (info?["SUPublicEDKey"] as? String) ?? ""
        let feed = (info?["SUFeedURL"] as? String) ?? ""
        let keyOK = !key.isEmpty && !key.contains("REPLACE")
        let feedOK = feed.hasPrefix("https://") && !feed.contains("OWNER")
        return keyOK && feedOK
    }
}
