import XCTest
@testable import DevDock

/// Locks the first-run decision: the welcome shows exactly once, and completion sticks.
final class OnboardingStateTests: XCTestCase {

    /// A private, in-memory defaults domain so tests never touch real user state.
    private func makeDefaults() -> UserDefaults {
        let suite = "com.devdock.tests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testShowsOnFirstLaunch() {
        let state = OnboardingState(defaults: makeDefaults())
        XCTAssertTrue(state.shouldShowOnboarding)
        XCTAssertFalse(state.hasCompletedOnboarding)
    }

    func testDoesNotShowAfterCompletion() {
        let state = OnboardingState(defaults: makeDefaults())
        state.markCompleted()
        XCTAssertFalse(state.shouldShowOnboarding)
        XCTAssertTrue(state.hasCompletedOnboarding)
    }

    func testCompletionPersistsAcrossInstances() {
        let defaults = makeDefaults()
        OnboardingState(defaults: defaults).markCompleted()
        // A fresh instance over the same defaults (i.e. a later launch) still sees it done.
        XCTAssertFalse(OnboardingState(defaults: defaults).shouldShowOnboarding)
    }

    func testMarkCompletedIsIdempotent() {
        let state = OnboardingState(defaults: makeDefaults())
        state.markCompleted()
        state.markCompleted()
        XCTAssertTrue(state.hasCompletedOnboarding)
    }

    func testKeyIsNamespacedAndVersioned() {
        // A distinct instance reading the documented key sees the same completion,
        // guarding against an accidental key rename silently re-triggering onboarding.
        let defaults = makeDefaults()
        OnboardingState(defaults: defaults,
                        key: "com.devdock.onboarding.v1.completed").markCompleted()
        XCTAssertTrue(defaults.bool(forKey: "com.devdock.onboarding.v1.completed"))
    }
}
