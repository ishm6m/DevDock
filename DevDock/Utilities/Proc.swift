import Darwin
import Foundation

/// Thin, safe Swift wrappers around the Darwin `libproc` and `sysctl` APIs.
///
/// DevDock uses these to gather per-process metadata (working directory, memory,
/// CPU time, thread count, launch time, full command line) **without spawning a
/// single subprocess**. Port-to-PID mapping goes through `libproc` too — see
/// `PortScanner`, which replaced the old per-refresh `lsof` fork.
///
/// All calls are best-effort: they return `nil` on failure (permission denied,
/// the process died between calls, etc.) and never trap.
enum Proc {

    // `proc_pidinfo` flavors. Declared with raw values so we don't depend on the
    // C macros being imported into Swift.
    private static let PID_TASKINFO: Int32 = 4        // PROC_PIDTASKINFO
    private static let PID_TBSDINFO: Int32 = 3        // PROC_PIDTBSDINFO
    private static let PID_VNODEPATHINFO: Int32 = 9   // PROC_PIDVNODEPATHINFO
    private static let PATH_MAX_BYTES: Int32 = 4096   // 4 * MAXPATHLEN
    private static let ALL_PIDS: UInt32 = 1           // PROC_ALL_PIDS

    /// A single point-in-time sample of a process's kernel-reported state.
    struct Snapshot {
        let pid: Int32
        let name: String            // kernel-registered short name (accurate, may be truncated to 32 chars)
        let executablePath: String?
        let arguments: [String]     // full argv (untruncated), argv[0] first
        let workingDirectory: String?
        let residentMemoryBytes: UInt64
        let cpuTimeNanoseconds: UInt64
        let uid: uid_t
        let startTime: Date

        /// The full command line as a single string, or the executable path as a fallback.
        var commandLine: String {
            if !arguments.isEmpty {
                return arguments.joined(separator: " ")
            }
            return executablePath ?? name
        }
    }

    /// DevDock's own process identifier. Never a valid signal target.
    static let ownPID: Int32 = getpid()

    /// Whether `pid` is a safe target for `kill(2)`.
    ///
    /// This is the single most important safety gate in the app. `kill(2)`
    /// interprets non-positive PIDs specially:
    ///   - `kill(0, sig)`  → signals **every** process in the caller's process
    ///     group (which includes DevDock itself),
    ///   - `kill(-1, sig)` → signals every process the caller may signal,
    ///   - `kill(-g, sig)` → signals the whole process group `g`.
    ///
    /// A stale or malformed `DevServer` carrying `pid == 0` would therefore take
    /// DevDock down along with its children. We refuse anything that isn't a
    /// specific, real, *other* process: PID must be `> 1` (never 0, negative, or
    /// launchd) and must not be DevDock itself.
    static func isSafeToSignal(_ pid: Int32) -> Bool {
        pid > 1 && pid != ownPID
    }

    /// Whether a process with the given PID currently exists.
    ///
    /// `kill(pid, 0)` performs no signal delivery: it returns success if the
    /// process exists and we may signal it, and `EPERM` if it exists but is owned
    /// by another user. Both mean "alive". Non-positive PIDs are rejected outright
    /// so this can never be used as a liveness probe that accidentally targets the
    /// process group (see `isSafeToSignal`).
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// The absolute path of a process's executable, if readable.
    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX_BYTES))
        let result = proc_pidpath(pid, &buffer, UInt32(PATH_MAX_BYTES))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The Mach task info: memory, cumulative CPU time, and thread count.
    static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PID_TASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    /// All process IDs currently running on the system.
    static func allPIDs() -> [Int32] {
        let sizeBytes = proc_listpids(ALL_PIDS, 0, nil, 0)
        guard sizeBytes > 0 else { return [] }
        let capacity = Int(sizeBytes) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: capacity)
        let written = proc_listpids(ALL_PIDS, 0, &pids, sizeBytes)
        guard written > 0 else { return [] }
        let count = Int(written) / MemoryLayout<Int32>.size
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    /// The parent PID of a process, if readable.
    static func parentPID(_ pid: Int32) -> Int32? {
        guard let info = bsdInfo(pid) else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }

    /// The kernel-registered short name of a process (accurate, may be truncated).
    static func name(_ pid: Int32) -> String? {
        guard let info = bsdInfo(pid) else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        if !name.isEmpty { return name }
        let comm = withUnsafeBytes(of: info.pbi_comm) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return comm.isEmpty ? nil : comm
    }

    /// The BSD process info: owner uid, registered name, and start time.
    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PID_TBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    /// The current working directory of a process, resolved from its vnode info.
    ///
    /// This is what lets DevDock locate a project without ever running `lsof -d cwd`.
    static func currentWorkingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PID_VNODEPATHINFO, 0, &info, size)
        guard result == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty ? nil : path
    }

    /// The full, untruncated argument vector of a process via `KERN_PROCARGS2`.
    ///
    /// `lsof` and `ps` truncate the command; this returns the real argv so the
    /// framework detector and the restart command have the exact invocation.
    /// Returns `nil` for processes we can't read (typically owned by another user).
    static func arguments(_ pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBufferPointer { raw -> [String]? in
            guard let base = raw.baseAddress else { return nil }
            let end = base + size

            // Layout: [argc: Int32][exec_path\0][padding \0...][arg0\0 arg1\0 ...]
            var argc: Int32 = 0
            withUnsafeMutableBytes(of: &argc) { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(start: base, count: MemoryLayout<Int32>.size))
            }
            guard argc > 0 else { return nil }

            var cursor = base + MemoryLayout<Int32>.size
            // Skip the executable path string.
            while cursor < end, cursor.pointee != 0 { cursor += 1 }
            // Skip the null padding between the exec path and argv[0].
            while cursor < end, cursor.pointee == 0 { cursor += 1 }

            var args: [String] = []
            while cursor < end, args.count < Int(argc) {
                let token = String(cString: cursor)
                args.append(token)
                cursor += token.utf8.count + 1 // step past the token and its terminator
            }
            return args.isEmpty ? nil : args
        }
    }

    /// Gathers a full snapshot for a PID in a handful of syscalls.
    static func snapshot(_ pid: Int32) -> Snapshot? {
        guard let bsd = bsdInfo(pid) else { return nil }
        let task = taskInfo(pid)

        let name = withUnsafeBytes(of: bsd.pbi_name) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        let comm = withUnsafeBytes(of: bsd.pbi_comm) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }

        return Snapshot(
            pid: pid,
            name: name.isEmpty ? comm : name,
            executablePath: executablePath(pid),
            arguments: arguments(pid) ?? [],
            workingDirectory: currentWorkingDirectory(pid),
            residentMemoryBytes: task?.pti_resident_size ?? 0,
            cpuTimeNanoseconds: (task.map { $0.pti_total_user + $0.pti_total_system }) ?? 0,
            uid: bsd.pbi_uid,
            startTime: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec))
        )
    }
}
