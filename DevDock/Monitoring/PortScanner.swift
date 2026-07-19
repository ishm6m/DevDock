import Foundation

/// A single listening socket discovered by lsof: a PID bound to a port.
struct PortScanRecord: Hashable {
    let pid: Int32
    let command: String
    let port: Int
    let address: String
}

/// Discovers listening TCP ports using a single `lsof` invocation per refresh.
///
/// We use lsof's machine-readable field output (`-F`) rather than parsing its
/// columnar text, which keeps the parser robust and unit-testable. `lsof` is the
/// most reliable cross-version way to enumerate listening sockets on macOS; all
/// richer per-process metadata comes from `libproc` afterward (see `ProcessMonitor`).
final class PortScanner: @unchecked Sendable {

    private let runner: CommandRunner
    private let lsofPath = "/usr/sbin/lsof"

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func scan() async -> [PortScanRecord] {
        // -n: no DNS, -P: numeric ports, +c 0: full command names,
        // -sTCP:LISTEN: only listening sockets, -Fpcn: emit PID/command/name fields.
        let result = await runner.run(
            lsofPath,
            arguments: ["-nP", "+c", "0", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        )
        guard result.launched else {
            Log.discovery.error("lsof did not launch; is it present at \(self.lsofPath, privacy: .public)?")
            return []
        }
        return PortScanner.parse(result.standardOutput)
    }

    /// Parses lsof `-F` field output into scan records. Pure and deterministic.
    ///
    /// Field output groups files under each process. Process-level fields (`p`, `c`)
    /// appear once; the network name field (`n`) appears once per listening socket.
    static func parse(_ output: String) -> [PortScanRecord] {
        var records: [PortScanRecord] = []
        var currentPID: Int32?
        var currentCommand = ""

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())

            switch tag {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
            case "c":
                currentCommand = value
            case "n":
                guard let pid = currentPID,
                      let parsed = parseAddress(value) else { continue }
                records.append(PortScanRecord(
                    pid: pid,
                    command: currentCommand,
                    port: parsed.port,
                    address: parsed.address
                ))
            default:
                break
            }
        }
        return records
    }

    /// Splits an lsof network name like `*:3000`, `127.0.0.1:5432`, or `[::1]:3000`
    /// into its address and port. Uses the last colon so IPv6 addresses parse correctly.
    static func parseAddress(_ name: String) -> (address: String, port: Int)? {
        guard let colonIndex = name.lastIndex(of: ":") else { return nil }
        let address = String(name[name.startIndex..<colonIndex])
        let portString = String(name[name.index(after: colonIndex)...])
        guard let port = Int(portString), port > 0 else { return nil }
        return (address.isEmpty ? "*" : address, port)
    }
}
