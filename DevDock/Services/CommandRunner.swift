import Foundation

/// The outcome of running an external command.
struct CommandResult {
    let exitCode: Int32
    let standardOutput: String
    /// False when the executable could not be launched at all (missing binary, etc.).
    let launched: Bool

    var succeeded: Bool { launched && exitCode == 0 }

    static let notLaunched = CommandResult(exitCode: -1, standardOutput: "", launched: false)
}

/// Runs short-lived external commands via `Foundation.Process`.
///
/// Commands run off the main thread on a utility queue. Output is read to EOF
/// before waiting for exit, which is the correct ordering to avoid a pipe-buffer
/// deadlock for the small outputs DevDock consumes (lsof, docker, git-free reads).
final class CommandRunner: @unchecked Sendable {

    /// Directories searched when an executable is given by name rather than path.
    private static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Resolves an executable name to an absolute path, or returns `nil` if not found.
    static func resolveExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        if name.hasPrefix("/") {
            return fm.isExecutableFile(atPath: name) ? name : nil
        }
        var directories = searchPaths
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            directories += pathEnv.split(separator: ":").map(String.init)
        }
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func run(_ executable: String, arguments: [String]) async -> CommandResult {
        await run(executable, arguments: arguments, currentDirectory: nil)
    }

    func run(_ executable: String, arguments: [String], currentDirectory: URL?) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let resolved = CommandRunner.resolveExecutable(executable) else {
                    continuation.resume(returning: .notLaunched)
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: resolved)
                process.arguments = arguments
                if let currentDirectory {
                    process.currentDirectoryURL = currentDirectory
                }

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    Log.commands.error("Failed to launch \(resolved, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .notLaunched)
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                // Drain stderr so a chatty child can't block on a full pipe; we don't keep it.
                _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(decoding: outputData, as: UTF8.self),
                    launched: true
                ))
            }
        }
    }
}
