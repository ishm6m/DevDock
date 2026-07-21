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
        /// A monotonic counter rather than a `UUID`: a chatty server emits thousands of
        /// lines a second, and this is both cheaper to mint and cheaper to hash.
        let id: Int
        let text: String
        let isError: Bool
        let date: Date
    }

    /// Log buffers keyed by the launched process's PID.
    @Published private(set) var buffers: [Int32: [LogLine]] = [:]

    private var processes: [Int32: Process] = [:]
    private var nextLineID = 0
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
        let now = Date()
        // Append *through the subscript*. Binding `var lines = buffers[pid]` leaves the
        // dictionary holding a second reference to the storage, so the first append
        // triggers a copy-on-write of the whole buffer — up to 2,000 elements copied for
        // every chunk of output a server produces.
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            nextLineID += 1
            buffers[pid]?.append(LogLine(id: nextLineID, text: String(rawLine), isError: isError, date: now))
        }
        if let overflow = buffers[pid].map({ $0.count - maxLines }), overflow > 0 {
            buffers[pid]?.removeFirst(overflow)
        }
    }
}
