import Foundation

/// Computes per-process resource metrics from `libproc` snapshots.
///
/// CPU percentage requires two samples: it is the change in cumulative CPU time
/// divided by the wall-clock interval between refreshes. This class therefore
/// caches the previous CPU sample per PID. It is intentionally *not* an actor —
/// it is used exclusively inside `DiscoveryEngine`'s actor isolation, so its
/// mutable cache is already serialized.
final class ProcessMonitor {

    private struct CPUSample {
        let cpuTimeNanoseconds: UInt64
        let timestamp: Date
    }

    private var previousCPU: [Int32: CPUSample] = [:]

    /// Samples a process's live resource usage, or `nil` if it has gone away.
    /// CPU% is 0 on the first sample for a PID (no prior baseline yet).
    ///
    /// This deliberately reads *only* `proc_taskinfo`, not a full `Proc.snapshot`.
    /// Everything else a snapshot gathers — argv via `KERN_PROCARGS2`, the executable
    /// path, the vnode working directory — is static for the life of a PID and is
    /// cached by `DiscoveryEngine`, so fetching it on every tick cost three extra
    /// syscalls and several kilobytes of scratch buffers *per server, per refresh*.
    func usage(for pid: Int32, now: Date = Date()) -> ResourceUsage? {
        guard let task = Proc.taskInfo(pid) else {
            previousCPU[pid] = nil
            return nil
        }
        let cpuTimeNanoseconds = task.pti_total_user + task.pti_total_system

        var cpuPercent = 0.0
        if let previous = previousCPU[pid] {
            let elapsedNanoseconds = now.timeIntervalSince(previous.timestamp) * 1_000_000_000
            if elapsedNanoseconds > 0, cpuTimeNanoseconds >= previous.cpuTimeNanoseconds {
                let deltaCPU = Double(cpuTimeNanoseconds - previous.cpuTimeNanoseconds)
                cpuPercent = (deltaCPU / elapsedNanoseconds) * 100.0
            }
        }
        previousCPU[pid] = CPUSample(cpuTimeNanoseconds: cpuTimeNanoseconds, timestamp: now)

        return ResourceUsage(cpuPercent: cpuPercent, memoryBytes: task.pti_resident_size)
    }

    /// Drops cached CPU samples for PIDs that are no longer present, so the cache
    /// can't grow without bound.
    func prune(keeping activePIDs: Set<Int32>) {
        previousCPU = previousCPU.filter { activePIDs.contains($0.key) }
    }
}
