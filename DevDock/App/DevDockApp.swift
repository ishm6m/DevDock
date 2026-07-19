import SwiftUI

/// DevDock — a developer control center that lives in the macOS menu bar.
///
/// The app is menu-bar-only (`LSUIElement`), so the primary scene is a
/// `MenuBarExtra` in `.window` style hosting a rich SwiftUI panel. A `Settings`
/// scene provides preferences, and a keyed `WindowGroup` hosts live log windows.
@main
struct DevDockApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // IMPORTANT: the view model is held as a plain `let`, NOT a `@StateObject`.
    //
    // A `.window`-style `MenuBarExtra` panel is destroyed whenever its Scene is
    // rebuilt. `ObservableObject` observation is object-level, so if this App's
    // `body` were subscribed to the view model (via `@StateObject`/`@ObservedObject`),
    // *every* `objectWillChange` — a copy, a favorite toggle, a refresh, the feedback
    // toast — would re-evaluate `body`, rebuild the `MenuBarExtra`, and dismiss the
    // open panel out from under the user. Keeping it a plain reference means the Scene
    // is built once and stays put; the label and content views observe the model
    // themselves and update in place. Do not turn this back into a `@StateObject`.
    private let viewModel: MenuBarViewModel
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        self.environment = environment
        self.viewModel = MenuBarViewModel(environment: environment)
        // Hand the environment to the delegate, which starts monitoring once
        // NSApplication has finished launching.
        AppDelegate.pendingEnvironment = environment
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(store: environment.preferencesStore, updater: environment.updater)
        }

        WindowGroup(id: "logs", for: Int32.self) { $pid in
            LogWindowContainer(pid: pid, environment: environment)
        }
        .defaultSize(width: 660, height: 440)
    }
}

/// Bridges a keyed log window to a freshly-built `LogViewModel`.
struct LogWindowContainer: View {
    let pid: Int32?
    let environment: AppEnvironment

    var body: some View {
        LogWindowView(viewModel: LogViewModel(
            title: title,
            managedPID: pid,
            logService: environment.logService
        ))
    }

    private var title: String {
        guard let pid else { return "Logs" }
        if let server = environment.coordinator.servers.first(where: { $0.managedRootPID == pid }) {
            return "\(server.title) — Logs"
        }
        return "Logs — PID \(pid)"
    }
}
