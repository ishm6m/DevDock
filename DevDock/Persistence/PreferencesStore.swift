import Foundation
import AppKit
import ServiceManagement

/// Persists and applies user preferences.
///
/// Settings are stored as JSON in `UserDefaults`. Two preferences have side
/// effects that are applied here: appearance (overrides the app's `NSAppearance`)
/// and launch-at-login (registered via `SMAppService`, the modern replacement for
/// login-item shims).
@MainActor
final class PreferencesStore: ObservableObject {

    @Published var preferences: Preferences {
        didSet {
            persist()
            if preferences.appearance != oldValue.appearance { applyAppearance() }
            if preferences.launchAtLogin != oldValue.launchAtLogin { syncLaunchAtLogin() }
        }
    }

    private let defaults: UserDefaults
    private let storageKey = "com.devdock.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    /// Applies effects that should run at launch (invoked once from the app delegate).
    func applyInitialState() {
        applyAppearance()
        syncLaunchAtLogin()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func syncLaunchAtLogin() {
        do {
            let service = SMAppService.mainApp
            if preferences.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            Log.app.error("Failed to update launch-at-login: \(error.localizedDescription, privacy: .public)")
        }
    }
}
