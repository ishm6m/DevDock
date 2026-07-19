import Foundation

/// The result of attempting to terminate a process.
enum KillOutcome: Equatable {
    case terminated       // exited gracefully after SIGTERM
    case killed           // required SIGKILL escalation
    case alreadyGone      // process was not running
    case notPermitted     // owned by another user (EPERM)
    case refusedUnsafe    // target was invalid or DevDock itself — never signalled
    case failed           // unexpected failure

    /// Whether the process is no longer running as a result (or was already gone).
    var didStopProcess: Bool {
        switch self {
        case .terminated, .killed, .alreadyGone: return true
        case .notPermitted, .refusedUnsafe, .failed: return false
        }
    }

    /// A short, human-facing description for UI feedback.
    var userMessage: String {
        switch self {
        case .terminated: return "Server stopped"
        case .killed: return "Server force-quit"
        case .alreadyGone: return "Server already stopped"
        case .notPermitted: return "Can't stop — owned by another user"
        case .refusedUnsafe: return "Refused — unsafe process ID"
        case .failed: return "Couldn't stop the server"
        }
    }
}

/// Graceful process termination with escalation.
///
/// Sends `SIGTERM` first and gives the process a grace period to shut down cleanly
/// (letting dev servers flush and release their port). If it's still alive after
/// the grace period, escalates to `SIGKILL`.
enum KillStrategy {

    static func terminate(pid: Int32, gracePeriod: TimeInterval = 3.0) async -> KillOutcome {
        // Absolute safety gate: never signal a non-positive PID or DevDock itself.
        // A non-positive PID passed to kill(2) targets the whole process group and
        // would terminate DevDock. This must be checked before any kill() call —
        // including the liveness probe.
        guard Proc.isSafeToSignal(pid) else {
            Log.commands.fault("Refused to signal unsafe PID \(pid) (own PID is \(Proc.ownPID))")
            return .refusedUnsafe
        }

        guard Proc.isAlive(pid) else { return .alreadyGone }

        if kill(pid, SIGTERM) != 0 {
            switch errno {
            case ESRCH: return .alreadyGone
            case EPERM: return .notPermitted
            default: return .failed
            }
        }

        // Poll for graceful exit.
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if !Proc.isAlive(pid) { return .terminated }
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        }
        if !Proc.isAlive(pid) { return .terminated }

        // Escalate.
        if kill(pid, SIGKILL) != 0 {
            switch errno {
            case ESRCH: return .terminated
            case EPERM: return .notPermitted
            default: return .failed
            }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .killed
    }
}
