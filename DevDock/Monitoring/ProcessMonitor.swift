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

    /// The static + dynamic facts we can learn about a process from the kernel.
    struct Metrics {
        let snapshot: Proc.Snapshot
        let usage: ResourceUsage
    }

    private var previousCPU: [Int32: CPUSample] = [:]

    /// Samples a process and returns its metrics, or `nil` if it has gone away.
    /// CPU% is 0 on the first sample for a PID (no prior baseline yet).
    func metrics(for pid: Int32, now: Date = Date()) -> Metrics? {
        guard let snapshot = Proc.snapshot(pid) else {
            previousCPU[pid] = nil
            return nil
        }

        var cpuPercent = 0.0
        if let previous = previousCPU[pid] {
            let elapsedNanoseconds = now.timeIntervalSince(previous.timestamp) * 1_000_000_000
            if elapsedNanoseconds > 0, snapshot.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds {
                let deltaCPU = Double(snapshot.cpuTimeNanoseconds - previous.cpuTimeNanoseconds)
                cpuPercent = (deltaCPU / elapsedNanoseconds) * 100.0
            }
        }
        previousCPU[pid] = CPUSample(cpuTimeNanoseconds: snapshot.cpuTimeNanoseconds, timestamp: now)

        let usage = ResourceUsage(
            cpuPercent: cpuPercent,
            memoryBytes: snapshot.residentMemoryBytes
        )
        return Metrics(snapshot: snapshot, usage: usage)
    }

    /// Drops cached CPU samples for PIDs that are no longer present, so the cache
    /// can't grow without bound.
    func prune(keeping activePIDs: Set<Int32>) {
        previousCPU = previousCPU.filter { activePIDs.contains($0.key) }
    }
}
