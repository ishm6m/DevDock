import Foundation

/// What the auto-stop policy wants done with a server on this refresh pass.
enum AutoStopAction: Equatable {
    /// Nothing to do — either not a candidate, or waiting out the grace window.
    case none
    /// Just became an idle+old candidate — post the "will auto-stop" heads-up.
    case warn
    /// Has stayed an idle candidate through the grace window — stop it now.
    case stop
}

/// The pure, testable policy behind "auto-stop idle servers."
///
/// Deciding *when* to reap a forgotten server is a small state machine over two signals
/// (uptime and CPU) plus a carried-forward timestamp. Like `ServerAttention.evaluate`,
/// this is kept free of any clock, process access, or preferences lookup so the whole
/// policy is unit-testable; `AutoStopController` owns the side effects and the per-PID
/// state, and reuses `ServerAttention.idleCPUPercent` so "idle" means the same thing here
/// as it does for the forgotten flag.
enum AutoStop {

    /// How long a server must remain an idle candidate after the first warning before it
    /// is actually stopped. In-memory only (see `AutoStopController`), so it resets each
    /// launch — a server is never stopped in a session without first being warned in it.
    static let graceInterval: TimeInterval = 5 * 60

    /// Decides the action for one server and the candidate marker to carry into the next
    /// pass.
    ///
    /// A server *qualifies* when it has been up at least `thresholdSeconds` **and** is
    /// near-idle (CPU below `ServerAttention.idleCPUPercent`). The transitions are:
    /// - doesn't qualify → `(.none, nil)` — any pending stop is cancelled.
    /// - newly qualifies → `(.warn, now)` — start the grace window.
    /// - qualifies, still inside the window → `(.none, candidateSince)`.
    /// - qualifies, window elapsed → `(.stop, candidateSince)`.
    ///
    /// Because a qualifying lapse (e.g. a CPU spike) clears the marker, a server that goes
    /// busy mid-window is never stopped without a fresh warning when it later goes idle.
    ///
    /// - Parameters:
    ///   - uptime: how long the process has been running.
    ///   - cpuPercent: the current CPU sample.
    ///   - thresholdSeconds: idle-uptime beyond which the server may be auto-stopped.
    ///   - candidateSince: when this process first qualified in a prior pass, or `nil`.
    ///   - now: the evaluation time (injected for testing).
    /// - Returns: the action to take and the marker to store for next time.
    static func evaluate(
        uptime: TimeInterval,
        cpuPercent: Double,
        thresholdSeconds: TimeInterval,
        candidateSince: Date?,
        now: Date
    ) -> (action: AutoStopAction, candidateSince: Date?) {
        let qualifies = uptime >= thresholdSeconds && cpuPercent < ServerAttention.idleCPUPercent

        guard qualifies else { return (.none, nil) }

        guard let since = candidateSince else {
            // First pass it qualifies: warn and open the grace window.
            return (.warn, now)
        }

        if now.timeIntervalSince(since) >= graceInterval {
            return (.stop, since)
        }
        return (.none, since)
    }
}
