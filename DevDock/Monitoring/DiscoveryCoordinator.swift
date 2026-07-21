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

    /// True while the menu bar panel is on screen. The user is watching, so the loop
    /// polls faster; a scan costs ~25ms, so this is cheap for the moments it's set.
    var isPanelOpen = false {
        didSet { if isPanelOpen { lastChangeAt = Date() } }
    }

    /// When something last actually changed (or the user last interacted). Drives the
    /// idle backoff in `nextInterval`.
    private var lastChangeAt = Date()

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
                await self?.coalescedRefresh()
                let nanos = UInt64(max(0.5, self?.nextInterval() ?? 3) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    /// How long to wait before the next pass.
    ///
    /// Open panel wins outright — the user is watching, so a server that starts under
    /// their eyes must appear immediately (`min` keeps an explicitly faster preference
    /// intact). With the panel closed a pass only feeds the menu bar count and the
    /// started/stopped notifications, so the loop backs off the longer nothing happens:
    /// a dev machine sits unchanged for hours at a time, and each avoided pass is a
    /// timer wake-up plus an `lsof` fork that nobody was waiting on. Any change — or any
    /// user interaction — resets `lastChangeAt` and snaps the cadence back to `base`.
    private func nextInterval() -> Double {
        let base = preferencesStore.preferences.refreshInterval
        if isPanelOpen { return min(1, base) }

        let quiet = Date().timeIntervalSince(lastChangeAt)
        var interval = base
        if quiet > Self.deepIdleAfter {
            interval = max(base, 10)
        } else if quiet > Self.idleAfter {
            interval = max(base, 5)
        }
        // Low Power Mode: the user has asked the system to conserve and nothing is on
        // screen to go stale, so start at the slowest rung.
        if ProcessInfo.processInfo.isLowPowerModeEnabled { interval = max(interval, 10) }
        return interval
    }

    private static let idleAfter: TimeInterval = 30
    private static let deepIdleAfter: TimeInterval = 120

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
        // Everything except the timer loop reaches discovery through here, and all of it
        // is user-initiated (panel opened, kill, restart, manual refresh). Treat it as
        // interaction and restore the fast cadence.
        lastChangeAt = Date()
        await coalescedRefresh()
    }

    private func coalescedRefresh() async {
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
        // Docker and tunnels feed panel-only sections — the menu bar shows the server
        // count, and notifications cover servers and port conflicts. Probing them with
        // the panel closed forked `docker ps` and named every PID on the system, every
        // few seconds, to produce data nothing could display. Opening the panel refreshes
        // immediately, so the sections are populated before they can be read.
        let snapshot = await engine.discover(preferences: preferences, probeAuxiliary: isPanelOpen)

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

        // Assign only what changed — every assignment to a @Published property fires
        // objectWillChange and re-renders the panel and the menu bar label.
        //
        // `servers` is the awkward one: live CPU/memory means it is *never* equal to the
        // previous pass, so it published on every single tick. While the panel is closed
        // the only thing on screen is the count, and nobody can see a CPU number move, so
        // a pass that differs by nothing but resource jitter is dropped. Opening the panel
        // refreshes immediately, so the numbers are never stale when they become visible.
        let serversChanged = Self.differsBeyondResources(servers, flagged)
        if servers != flagged, isPanelOpen || serversChanged {
            servers = flagged
        }
        var changed = serversChanged
        if databases != snapshot.databases { databases = snapshot.databases; changed = true }
        if containers != snapshot.containers { containers = snapshot.containers; changed = true }
        if tunnels != snapshot.tunnels { tunnels = snapshot.tunnels; changed = true }
        if conflictPorts != snapshot.conflictPorts { conflictPorts = snapshot.conflictPorts; changed = true }

        // Something real happened: stay on the fast cadence.
        if changed { lastChangeAt = Date() }

        // `notice` is persisted to the unified log store; at one line per pass that was a
        // disk write every few seconds, forever, for a message that says "nothing
        // happened". Only transitions are worth keeping — steady state goes to `debug`,
        // which stays in memory unless someone is actively streaming.
        let summary = "Discovered \(snapshot.servers.count) servers, \(snapshot.databases.count) databases, \(snapshot.containers.count) containers, \(snapshot.tunnels.count) tunnels"
        if changed {
            Log.discovery.notice("\(summary, privacy: .public)")
        } else {
            Log.discovery.debug("\(summary, privacy: .public)")
        }
    }

    /// True when two server lists differ in anything other than live resource usage —
    /// i.e. a server appeared, went away, was reordered, or changed a displayed
    /// attribute. Used to decide whether a pass is worth publishing.
    private static func differsBeyondResources(_ old: [DevServer], _ new: [DevServer]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) {
            var normalized = a
            normalized.resources = b.resources
            if normalized != b { return true }
        }
        return false
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
