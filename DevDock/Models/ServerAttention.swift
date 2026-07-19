import Foundation

/// Why a running server is flagged as needing attention.
///
/// This is the heart of DevDock's reason to exist: forgotten dev servers hold ports,
/// drain the battery, and burn CPU. Rather than only *listing* what's running, DevDock
/// proactively surfaces the ones you've likely forgotten (long uptime) or that are
/// burning resources (sustained high CPU) so you actually notice them.
struct ServerAttention: Equatable, Hashable {
    /// Running longer than the configured threshold *while sitting near-idle* (low CPU)
    /// — the classic forgotten server. Gating on low CPU keeps the "Idle" label honest:
    /// a long-running server that's actively working isn't forgotten, you're using it.
    var isForgotten: Bool = false
    /// CPU has stayed at or above the high-CPU threshold long enough to count as
    /// sustained (not just a momentary build spike).
    var isHighCPU: Bool = false

    var needsAttention: Bool { isForgotten || isHighCPU }

    static let none = ServerAttention()

    /// Sustained CPU at or above this percent flags a server as burning resources.
    /// Matches the threshold at which the server row already tints its CPU metric.
    static let highCPUPercent: Double = 80

    /// CPU must stay above the threshold for at least this long before flagging, so a
    /// brief compile/build spike doesn't trip it.
    static let highCPUSustainedSeconds: TimeInterval = 45

    /// A long-running server is only "forgotten" if it's below this CPU — otherwise it's
    /// actively doing work and shouldn't be labelled idle.
    static let idleCPUPercent: Double = 5

    /// Pure evaluation of a server's attention state from timing inputs, returning the
    /// flags plus the (possibly updated) "high CPU since" marker to carry into the next
    /// refresh. Kept pure — no clock, no process access — so it's fully unit-testable.
    ///
    /// - Parameters:
    ///   - launchDate: when the process started.
    ///   - cpuPercent: the current CPU sample.
    ///   - forgottenAfter: uptime beyond which a server is considered forgotten.
    ///   - now: the evaluation time (injected for testing).
    ///   - highCPUSince: when this process first crossed the CPU threshold in a prior
    ///     pass, or `nil` if it wasn't over the threshold last time.
    /// - Returns: the attention flags and the marker to store for next time.
    static func evaluate(
        launchDate: Date,
        cpuPercent: Double,
        forgottenAfter: TimeInterval,
        now: Date,
        highCPUSince: Date?
    ) -> (attention: ServerAttention, highCPUSince: Date?) {
        let forgotten = now.timeIntervalSince(launchDate) >= forgottenAfter
            && cpuPercent < idleCPUPercent

        let since: Date?
        let highCPU: Bool
        if cpuPercent >= highCPUPercent {
            let start = highCPUSince ?? now
            since = start
            highCPU = now.timeIntervalSince(start) >= highCPUSustainedSeconds
        } else {
            since = nil
            highCPU = false
        }

        return (ServerAttention(isForgotten: forgotten, isHighCPU: highCPU), since)
    }
}
