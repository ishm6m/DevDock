import SwiftUI
import AppKit

/// The preferences window, presented via the SwiftUI `Settings` scene.
struct PreferencesView: View {
    @ObservedObject var store: PreferencesStore
    /// Not observed: the only mutable state is Sparkle's own persisted setting, driven
    /// through a manual `Binding` below.
    let updater: SparkleUpdater

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            monitoringTab
                .tabItem { Label("Monitoring", systemImage: "waveform.path.ecg") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch DevDock at login", isOn: $store.preferences.launchAtLogin)
                Toggle("Confirm before killing a server", isOn: $store.preferences.confirmBeforeKill)
                Toggle("Show notifications", isOn: $store.preferences.showNotifications)
            }
            Section("Appearance") {
                Picker("Theme", selection: $store.preferences.appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
            updatesSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Updates

    @ViewBuilder
    private var updatesSection: some View {
        if updater.supportsUpdates {
            Section {
                // Bound straight to Sparkle's persisted setting — no mirror in
                // `Preferences`, so there's one source of truth.
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check for Updates…") { updater.checkForUpdates() }
            } header: {
                Text("Updates")
            } footer: {
                Text("DevDock updates itself with Sparkle and verifies each update's signature before installing. Checks contact the DevDock release feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Monitoring

    private var monitoringTab: some View {
        Form {
            Section("Discovery") {
                Picker("Refresh interval", selection: $store.preferences.refreshInterval) {
                    ForEach(Preferences.refreshIntervalOptions, id: \.self) { interval in
                        Text(interval == 1 ? "1 second" : "\(Int(interval)) seconds").tag(interval)
                    }
                }
            }
            Section {
                Toggle("Docker containers", isOn: $store.preferences.monitorDocker)
                Toggle("Databases (Postgres, Redis, MongoDB, MySQL, Supabase)", isOn: $store.preferences.monitorDatabases)
                Toggle("Tunnels (ngrok, Cloudflare, LocalTunnel)", isOn: $store.preferences.monitorTunnels)
            } header: {
                Text("Detect")
            } footer: {
                Text("Disabling a category skips its work each refresh, saving a little CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Flag forgotten & high-CPU servers", isOn: $store.preferences.flagForgottenServers)
                Picker("Consider forgotten after", selection: $store.preferences.forgottenAfterHours) {
                    ForEach(Preferences.forgottenAfterHoursOptions, id: \.self) { hours in
                        Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                    }
                }
                .disabled(!store.preferences.flagForgottenServers)
            } header: {
                Text("Attention")
            } footer: {
                Text("Tags long-running or high-CPU servers in the panel and sends a one-time nudge so you can reclaim ports, battery, and CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            autoStopSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var autoStopSection: some View {
        Section {
            Toggle("Automatically stop idle servers", isOn: $store.preferences.autoStopEnabled)
            Picker("Stop after", selection: $store.preferences.autoStopAfterHours) {
                ForEach(Preferences.autoStopAfterHoursOptions, id: \.self) { hours in
                    Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                }
            }
            .disabled(!store.preferences.autoStopEnabled)
        } header: {
            Text("Automatic cleanup")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gracefully stops dev servers that have been running past this long **while sitting idle**. Pinned favorites, databases, Docker, and tunnels are never touched. You're warned before anything is stopped.")
                if store.preferences.autoStopEnabled && !store.preferences.showNotifications {
                    Label("Turn on notifications to be warned before a server is stopped.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            Text("DevDock").font(.title2.bold())
            Text("Version \(appVersion)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Text("A developer control center for your menu bar. Open source under the MIT License.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Text("DevDock is not sandboxed so it can inspect and control your local dev processes. It only ever acts on processes you own, and never signals its own process.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
