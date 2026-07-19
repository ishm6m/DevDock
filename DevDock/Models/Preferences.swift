import Foundation

/// The appearance modes offered in preferences.
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// User-configurable settings, persisted via `PreferencesStore`.
struct Preferences: Codable, Equatable {
    var refreshInterval: Double
    var showNotifications: Bool
    var confirmBeforeKill: Bool
    var launchAtLogin: Bool
    var appearance: Appearance
    var monitorDocker: Bool
    var monitorDatabases: Bool
    var monitorTunnels: Bool

    /// Flag servers that are likely forgotten (long uptime) or burning CPU, with an
    /// in-panel tag and a one-time nudge notification.
    var flagForgottenServers: Bool
    /// Uptime, in hours, beyond which a low-activity server is considered forgotten.
    var forgottenAfterHours: Int

    /// Automatically stop dev servers that have been running past `autoStopAfterHours`
    /// *while sitting idle*. Opt-in and off by default — this is the one setting that
    /// lets DevDock take a destructive action on its own, so it stays conservative:
    /// idle-only, favorites exempt, and warned before acting (see `AutoStopController`).
    var autoStopEnabled: Bool
    /// Idle uptime, in hours, beyond which an idle server is auto-stopped.
    var autoStopAfterHours: Int

    /// Allowed refresh intervals surfaced in the UI (seconds).
    static let refreshIntervalOptions: [Double] = [1, 2, 3, 5, 10]

    /// Allowed "forgotten after" thresholds surfaced in the UI (hours).
    static let forgottenAfterHoursOptions: [Int] = [2, 4, 8, 12, 24]

    /// Allowed "auto-stop after" thresholds surfaced in the UI (hours). Includes a
    /// 1-hour option (the forgotten-flag list starts at 2h) for a snappier cleanup.
    static let autoStopAfterHoursOptions: [Int] = [1, 2, 4, 8, 12, 24]

    static let `default` = Preferences(
        refreshInterval: 3,
        showNotifications: true,
        confirmBeforeKill: true,
        launchAtLogin: false,
        appearance: .system,
        monitorDocker: true,
        monitorDatabases: true,
        monitorTunnels: true,
        flagForgottenServers: true,
        forgottenAfterHours: 8,
        autoStopEnabled: false,
        autoStopAfterHours: 2
    )
}

extension Preferences {
    private enum CodingKeys: String, CodingKey {
        case refreshInterval, showNotifications, confirmBeforeKill, launchAtLogin
        case appearance, monitorDocker, monitorDatabases, monitorTunnels
        case flagForgottenServers, forgottenAfterHours
        case autoStopEnabled, autoStopAfterHours
    }

    /// Decodes tolerantly: any key missing from stored JSON falls back to its default.
    /// This is what lets a new build add settings without wiping a user's existing
    /// preferences — the strict synthesized decoder would fail on the absent keys and
    /// reset everything to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.default
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? d.refreshInterval
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? d.showNotifications
        confirmBeforeKill = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforeKill) ?? d.confirmBeforeKill
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        monitorDocker = try c.decodeIfPresent(Bool.self, forKey: .monitorDocker) ?? d.monitorDocker
        monitorDatabases = try c.decodeIfPresent(Bool.self, forKey: .monitorDatabases) ?? d.monitorDatabases
        monitorTunnels = try c.decodeIfPresent(Bool.self, forKey: .monitorTunnels) ?? d.monitorTunnels
        flagForgottenServers = try c.decodeIfPresent(Bool.self, forKey: .flagForgottenServers) ?? d.flagForgottenServers
        forgottenAfterHours = try c.decodeIfPresent(Int.self, forKey: .forgottenAfterHours) ?? d.forgottenAfterHours
        autoStopEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoStopEnabled) ?? d.autoStopEnabled
        autoStopAfterHours = try c.decodeIfPresent(Int.self, forKey: .autoStopAfterHours) ?? d.autoStopAfterHours
    }
}
