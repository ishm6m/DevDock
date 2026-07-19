import XCTest
@testable import DevDock

/// Locks the tolerant decoding that lets a new build add settings without wiping a
/// user's existing preferences.
final class PreferencesMigrationTests: XCTestCase {

    func testDecodesOldJSONMissingNewKeysWithDefaults() throws {
        // JSON as an earlier build (before attention settings existed) would have stored it.
        let legacy = """
        {
          "refreshInterval": 5,
          "showNotifications": false,
          "confirmBeforeKill": false,
          "launchAtLogin": true,
          "appearance": "dark",
          "monitorDocker": false,
          "monitorDatabases": true,
          "monitorTunnels": false
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(Preferences.self, from: legacy)

        // Existing settings are preserved, not reset to defaults.
        XCTAssertEqual(prefs.refreshInterval, 5)
        XCTAssertFalse(prefs.showNotifications)
        XCTAssertFalse(prefs.confirmBeforeKill)
        XCTAssertTrue(prefs.launchAtLogin)
        XCTAssertEqual(prefs.appearance, .dark)
        XCTAssertFalse(prefs.monitorDocker)

        // New settings fall back to their defaults.
        XCTAssertEqual(prefs.flagForgottenServers, Preferences.default.flagForgottenServers)
        XCTAssertEqual(prefs.forgottenAfterHours, Preferences.default.forgottenAfterHours)
    }

    func testRoundTripPreservesAllFields() throws {
        var prefs = Preferences.default
        prefs.forgottenAfterHours = 12
        prefs.flagForgottenServers = false

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)

        XCTAssertEqual(decoded, prefs)
    }
}
