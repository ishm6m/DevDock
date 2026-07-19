import Foundation
import Combine

/// Drives the discovery refresh loop and publishes results to the UI.
///
/// This is the main-actor bridge between the off-main `DiscoveryEngine` and
/// SwiftUI: it owns the timer loop, diffs successive snapshots to emit lifecycle
/// notifications, and exposes `@Published` collections the views observe.
@MainActor
final class DiscoveryCoordinator: ObservableObject {

    @Published private(set) var servers: [DevServer] = []
    @Published private(set) var databases: [DatabaseService] = []
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var tunnels: [Tunnel] = []
    @Published private(set) var conflictPorts: Set<Int> = []
    @Published private(set) var isActive = false

    let engine: DiscoveryEngine
    private let notifications: NotificationManager
    private let preferencesStore: PreferencesStore
    private let autoStop: AutoStopController

    private var loopTask: Task<Void, Never>?
    private var lastServersByID: [String: DevServer] = [:]
    private var notifiedConflicts: Set<Int> = []
    private var isFirstPass = true

    /// Per-PID timestamp of when a process first crossed the high-CPU threshold, so we
    /// only flag *sustained* high CPU rather than momentary build spikes.
    private var highCPUSince: [Int32: Date] = [:]
    /// Server IDs already nudged for needing attention, so we alert at most once each.
    private var notifiedAttention: Set<String> = []

    // Coalesces overlapping refreshes: a request made while one is running sets a
    // flag so exactly one more pass runs afterwards, rather than piling up.
    private var isRefreshing = false
    private var refreshRequestedAgain = false

    var activeServerCount: Int { servers.count }

    init(engine: DiscoveryEngine, notifications: NotificationManager, preferencesStore: PreferencesStore, autoStop: AutoStopController) {
        self.engine = engine
        self.notifications = notifications
        self.preferencesStore = preferencesStore
        self.autoStop = autoStop
    }

    /// Starts the periodic refresh loop. Safe to call more than once.
    func start() {
        guard loopTask == nil else { return }
        isActive = true
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.preferencesStore.preferences.refreshInterval ?? 3
                let nanos = UInt64(max(0.5, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isActive = false
    }

    /// Performs a discovery pass immediately (also used after user actions).
    ///
    /// Refreshes are coalesced: if one is already running, this records that another
    /// pass is wanted and returns, so rapid triggers (timer tick + button taps) never
    /// stack up concurrent scans.
    func refresh() async {
        if isRefreshing {
            refreshRequestedAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshRequestedAgain = false
            await performRefresh()
        } while refreshRequestedAgain
    }

    private func performRefresh() async {
        let preferences = preferencesStore.preferences
        let snapshot = await engine.discover(preferences: preferences)

        // Capture the baseline flag before `applyNotifications` consumes it, so the
        // attention pass can also seed silently on the very first refresh.
        let isBaseline = isFirstPass
        let flagged = annotateAttention(snapshot.servers, preferences: preferences)

        applyNotifications(for: snapshot, preferences: preferences)
        applyAttentionNotifications(flagged, preferences: preferences, isBaseline: isBaseline)

        // Auto-stop idle servers (opt-in). Independent of the forgotten-flag feature: it
        // computes its own idle+threshold and always warns before stopping, so even the
        // first pass after launch only warns, never reaps.
        autoStop.process(snapshot.servers)

        // Assign only what changed. `servers` almost always changes (live CPU/memory),
        // but the auxiliary collections rarely do — skipping their assignment avoids
        // needlessly re-rendering those sections and keeps the panel from flickering.
        if servers != flagged { servers = flagged }
        if databases != snapshot.databases { databases = snapshot.databases }
        if containers != snapshot.containers { containers = snapshot.containers }
        if tunnels != snapshot.tunnels { tunnels = snapshot.tunnels }
        if conflictPorts != snapshot.conflictPorts { conflictPorts = snapshot.conflictPorts }

        Log.discovery.notice("Discovered \(snapshot.servers.count) servers, \(snapshot.databases.count) databases, \(snapshot.containers.count) containers, \(snapshot.tunnels.count) tunnels")
    }

    /// Emits started / stopped / conflict notifications by diffing against the last
    /// pass. The first pass only seeds the baseline so we never announce every
    /// server that was already running when DevDock launched.
    private func applyNotifications(for snapshot: DiscoverySnapshot, preferences: Preferences) {
        defer {
            lastServersByID = Dictionary(snapshot.servers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            notifiedConflicts = snapshot.conflictPorts
        }

        if isFirstPass {
            isFirstPass = false
            return
        }
        guard preferences.showNotifications else { return }

        let newIDs = Set(snapshot.servers.map(\.id))
        let oldIDs = Set(lastServersByID.keys)

        for server in snapshot.servers where !oldIDs.contains(server.id) {
            notifications.serverStarted(server)
        }
        for id in oldIDs.subtracting(newIDs) {
            if let server = lastServersByID[id] {
                notifications.serverStopped(title: server.title, port: server.port.number)
            }
        }
        for port in snapshot.conflictPorts.subtracting(notifiedConflicts) {
            notifications.portConflict(port: port)
        }
    }

    // MARK: - Attention (forgotten / high-CPU) detection

    /// Annotates each server with its attention state, carrying the per-PID high-CPU
    /// timing forward between refreshes so only *sustained* high CPU is flagged.
    private func annotateAttention(_ servers: [DevServer], preferences: Preferences) -> [DevServer] {
        guard preferences.flagForgottenServers else {
            highCPUSince.removeAll()
            return servers // attention stays `.none`
        }

        let now = Date()
        let forgottenAfter = TimeInterval(preferences.forgottenAfterHours) * 3600
        let livePIDs = Set(servers.map(\.pid))
        // Drop timing state for processes that are no longer around.
        highCPUSince = highCPUSince.filter { livePIDs.contains($0.key) }

        return servers.map { server in
            let (attention, since) = ServerAttention.evaluate(
                launchDate: server.launchDate,
                cpuPercent: server.resources.cpuPercent,
                forgottenAfter: forgottenAfter,
                now: now,
                highCPUSince: highCPUSince[server.pid]
            )
            highCPUSince[server.pid] = since
            var flagged = server
            flagged.attention = attention
            return flagged
        }
    }

    /// Fires a one-time nudge for each server that newly needs attention. The first
    /// pass (and any pass while alerts are off) only seeds the baseline, so a server
    /// already forgotten when DevDock launches never produces a burst of alerts.
    private func applyAttentionNotifications(_ servers: [DevServer], preferences: Preferences, isBaseline: Bool) {
        let flaggedIDs = Set(servers.filter { $0.attention.needsAttention }.map(\.id))
        // Forget IDs that dropped out so a later re-cross can alert again.
        notifiedAttention.formIntersection(flaggedIDs)

        guard !isBaseline, preferences.showNotifications, preferences.flagForgottenServers else {
            notifiedAttention = flaggedIDs // seed silently
            return
        }

        for id in flaggedIDs.subtracting(notifiedAttention) {
            if let server = servers.first(where: { $0.id == id }) {
                notifications.serverNeedsAttention(server)
            }
        }
        notifiedAttention = flaggedIDs
    }
}
