import Foundation

/// What the auto-stop policy wants done with a server on this refresh pass.
enum AutoStopAction: Equatable {
    case none
    /// Just became an idle+old candidate — post the "will auto-stop" heads-up.
    case warn
    /// Stayed an idle candidate through the grace window — stop it now.
    case stop
}

/// The pure policy behind "auto-stop idle servers" — no clock, no process access, no
/// preferences lookup, so it is fully unit-testable. `AutoStopController` below owns the
/// side effects and the per-PID state.
enum AutoStop {

    /// How long a server must stay an idle candidate after the first warning before it is
    /// actually stopped. In-memory only, so it resets each launch — a server is never
    /// stopped in a session without first being warned in it.
    static let graceInterval: TimeInterval = 5 * 60

    /// A server *qualifies* when it has been up at least `thresholdSeconds` **and** is
    /// near-idle. A qualifying lapse (a CPU spike) clears the marker, so a server that
    /// goes busy mid-window is never stopped without a fresh warning.
    static func evaluate(
        uptime: TimeInterval,
        cpuPercent: Double,
        thresholdSeconds: TimeInterval,
        candidateSince: Date?,
        now: Date
    ) -> (action: AutoStopAction, candidateSince: Date?) {
        guard uptime >= thresholdSeconds, cpuPercent < ServerAttention.idleCPUPercent else {
            return (.none, nil)
        }
        guard let since = candidateSince else { return (.warn, now) }
        return (now.timeIntervalSince(since) >= graceInterval ? .stop : .none, since)
    }
}

/// Drives the "auto-stop idle servers" policy each discovery pass.
///
/// This is the one place DevDock stops a process without a click, so it is deliberately
/// conservative. It owns the per-PID grace-window state and applies the exemptions, but
/// delegates the decision to the pure `AutoStop` evaluator above and the kill to
/// `ServerCommands.kill` — which routes through `KillStrategy`/`Proc.isSafeToSignal`, the
/// only sanctioned termination path. The coordinator calls `process(_:)` once per refresh.
@MainActor
final class AutoStopController {

    private let commands: ServerCommands
    private let favorites: FavoritesStore
    private let notifications: NotificationManager
    private let preferencesStore: PreferencesStore

    /// Per-PID timestamp of when a process first became an idle+old candidate, carried
    /// across passes so we only stop after the grace window. In-memory only, so it resets
    /// each launch — a server is never stopped in a session without a warning in it.
    private var candidateSince: [Int32: Date] = [:]
    /// PIDs whose stop is currently running, so overlapping passes never double-signal.
    private var inFlight: Set<Int32> = []

    init(
        commands: ServerCommands,
        favorites: FavoritesStore,
        notifications: NotificationManager,
        preferencesStore: PreferencesStore
    ) {
        self.commands = commands
        self.favorites = favorites
        self.notifications = notifications
        self.preferencesStore = preferencesStore
    }

    /// Evaluates the current server set and warns/stops idle candidates per the policy.
    func process(_ servers: [DevServer], now: Date = Date()) {
        let preferences = preferencesStore.preferences
        guard preferences.autoStopEnabled else {
            candidateSince.removeAll()
            return
        }

        let idleHours = preferences.autoStopAfterHours
        let thresholdSeconds = TimeInterval(idleHours) * 3600
        let graceMinutes = Int((AutoStop.graceInterval / 60).rounded())

        // Drop grace-window state for processes that are no longer around.
        let livePIDs = Set(servers.map(\.pid))
        candidateSince = candidateSince.filter { livePIDs.contains($0.key) }

        for server in servers {
            let pid = server.pid

            // A stop is already in flight for this PID — leave it alone until it settles.
            if inFlight.contains(pid) { continue }

            // Pinned favorites are never auto-stopped (mirrors "Kill All"); reset any
            // pending grace so unpinning later starts fresh with a warning.
            if favorites.isFavorite(server) {
                candidateSince[pid] = nil
                continue
            }

            let (action, marker) = AutoStop.evaluate(
                uptime: now.timeIntervalSince(server.launchDate),
                cpuPercent: server.resources.cpuPercent,
                thresholdSeconds: thresholdSeconds,
                candidateSince: candidateSince[pid],
                now: now
            )
            candidateSince[pid] = marker

            switch action {
            case .none:
                break
            case .warn:
                // The warning is what makes "warn first" meaningful, so it respects the
                // global notifications switch; with notifications off, auto-stop still
                // works but stops silently (documented in Preferences).
                if preferences.showNotifications {
                    notifications.serverWillAutoStop(server, idleHours: idleHours, inMinutes: graceMinutes)
                }
            case .stop:
                stop(server, idleHours: idleHours, notify: preferences.showNotifications)
            }
        }
    }

    private func stop(_ server: DevServer, idleHours: Int, notify: Bool) {
        let pid = server.pid
        inFlight.insert(pid)
        let title = server.title
        let port = server.port.number
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.commands.kill(server)
            if outcome.didStopProcess {
                Log.commands.info("Auto-stopped idle server \(title, privacy: .public) [PID \(pid)]")
                if notify {
                    self.notifications.serverAutoStopped(title: title, port: port, idleHours: idleHours)
                }
            } else {
                Log.commands.error("Auto-stop of \(title, privacy: .public) [PID \(pid)] did not stop it: \(String(describing: outcome), privacy: .public)")
            }
            // Reset state regardless of outcome: a stopped process is gone, and a process
            // we couldn't stop starts over with a fresh warning + full grace window rather
            // than retrying every refresh.
            self.candidateSince[pid] = nil
            self.inFlight.remove(pid)
        }
    }
}
