import Foundation

/// First-run state for the onboarding welcome.
///
/// Kept separate from `Preferences` on purpose: whether the user has seen the welcome
/// is app-lifecycle state, not a user-facing setting, so it must never appear in the
/// Preferences UI or ride along in the preferences round-trip. It lives under its own
/// versioned key so a future onboarding revision can choose to re-run by bumping the
/// version in the key.
///
/// The type is a thin, pure wrapper over `UserDefaults` (no AppKit, no windows) so the
/// "should we show the welcome?" decision is unit-testable without presenting UI —
/// mirroring how `ServerAttention` splits pure evaluation from the side-effecting
/// coordinator.
struct OnboardingState {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = "com.devdock.onboarding.v1.completed") {
        self.defaults = defaults
        self.key = key
    }

    /// Whether the welcome has already been completed or dismissed at least once.
    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: key)
    }

    /// Whether the welcome should be presented on this launch.
    var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding
    }

    /// Marks onboarding complete so it won't show again. Idempotent.
    func markCompleted() {
        defaults.set(true, forKey: key)
    }
}
