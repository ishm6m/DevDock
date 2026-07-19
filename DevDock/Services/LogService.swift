import Foundation
import Combine

/// Captures and buffers stdout/stderr for processes DevDock itself launches.
///
/// macOS cannot attach to the output of a process it did not spawn, so live logs
/// are only available for servers started or restarted through DevDock. When we
/// launch a process we keep its pipes and stream lines into a bounded ring buffer
/// keyed by PID. Child processes inherit these pipes, so a `npm run dev` wrapper's
/// child output is captured too.
@MainActor
final class LogService: ObservableObject {

    struct LogLine: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let isError: Bool
        let date: Date
    }

    /// Log buffers keyed by the launched process's PID.
    @Published private(set) var buffers: [Int32: [LogLine]] = [:]

    private var processes: [Int32: Process] = [:]
    private let maxLines = 2_000

    /// Begins capturing output for a launched process. The process must have `Pipe`
    /// instances set for `standardOutput` and `standardError`.
    func register(process: Process, pid: Int32) {
        processes[pid] = process
        buffers[pid] = []
        attach(pipe: process.standardOutput as? Pipe, pid: pid, isError: false)
        attach(pipe: process.standardError as? Pipe, pid: pid, isError: true)
    }

    func hasBuffer(forPID pid: Int32) -> Bool {
        buffers[pid] != nil
    }

    func lines(forPID pid: Int32) -> [LogLine] {
        buffers[pid] ?? []
    }

    /// Stops capturing and discards the buffer for a PID (e.g. before a restart).
    func discard(pid: Int32) {
        if let pipe = processes[pid]?.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if let pipe = processes[pid]?.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        processes[pid] = nil
        buffers[pid] = nil
    }

    private func attach(pipe: Pipe?, pid: Int32, isError: Bool) {
        guard let pipe else { return }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.append(pid: pid, text: text, isError: isError)
            }
        }
    }

    private func append(pid: Int32, text: String, isError: Bool) {
        guard buffers[pid] != nil else { return }
        var lines = buffers[pid] ?? []
        let now = Date()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lines.append(LogLine(text: String(rawLine), isError: isError, date: now))
        }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        buffers[pid] = lines
    }
}
