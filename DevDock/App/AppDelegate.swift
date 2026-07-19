import AppKit
import UserNotifications

/// Handles application lifecycle and notification presentation.
///
/// The `AppEnvironment` is handed over from `DevDockApp.init` via `pendingEnvironment`
/// so that startup work (which touches `NSApp`) runs once `NSApplication` is fully
/// initialized in `applicationDidFinishLaunching`.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by `DevDockApp.init` before the delegate callbacks fire.
    static var pendingEnvironment: AppEnvironment?

    private var environment: AppEnvironment?
    private var onboardingController: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppDelegate.pendingEnvironment
        self.environment = environment

        UNUserNotificationCenter.current().delegate = self

        environment?.preferencesStore.applyInitialState()

        // Present the first-run welcome (menu-bar apps launch invisibly). On a first
        // run the welcome owns the notification prompt so it fires from a deliberate
        // tap with context, not cold at launch where it gets denied. On later launches
        // request normally — a no-op once the user has already answered.
        let onboarding = OnboardingController(
            state: OnboardingState(),
            onEnableNotifications: { [weak self] in
                self?.environment?.notificationManager.requestAuthorization()
            }
        )
        onboardingController = onboarding
        if !onboarding.presentIfNeeded() {
            environment?.notificationManager.requestAuthorization()
        }

        environment?.coordinator.start()

        // Start background update checks. A no-op in builds from source (no release
        // feed/key configured); see `SparkleUpdater`.
        environment?.updater.startUpdater()

        Log.app.info("DevDock launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.coordinator.stop()
    }

    // Present notifications as banners even though DevDock has no regular windows.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
