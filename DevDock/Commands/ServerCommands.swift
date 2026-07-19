import Foundation
import AppKit

/// Executes the per-server actions surfaced in the UI.
///
/// Kill and restart coordinate with the `DiscoveryEngine` (to manage the "started
/// by DevDock" set) and the `LogService` (to own or discard captured output).
@MainActor
final class ServerCommands {

    private let engine: DiscoveryEngine
    private let logService: LogService

    init(engine: DiscoveryEngine, logService: LogService) {
        self.engine = engine
        self.logService = logService
    }

    // MARK: - Navigation actions

    func open(_ server: DevServer) {
        NSWorkspace.shared.open(server.localURL)
        Log.commands.info("Open \(server.localURL.absoluteString, privacy: .public)")
    }

    func open(url: URL) {
        NSWorkspace.shared.open(url)
        Log.commands.info("Open \(url.absoluteString, privacy: .public)")
    }

    /// Reveals the project root (or working directory) in Finder.
    @discardableResult
    func reveal(_ server: DevServer) -> Bool {
        guard let path = server.project?.rootPath ?? server.workingDirectory,
              FileManager.default.fileExists(atPath: path) else {
            Log.commands.error("Reveal failed for \(server.pid): no readable project path")
            NSSound.beep()
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        Log.commands.info("Reveal \(path, privacy: .public)")
        return true
    }

    func copyURL(_ server: DevServer) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(server.localURL.absoluteString, forType: .string)
        Log.commands.info("Copy URL \(server.localURL.absoluteString, privacy: .public)")
    }

    func copyConnectionString(_ database: DatabaseService) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(database.connectionString, forType: .string)
        Log.commands.info("Copy connection string \(database.connectionString, privacy: .public)")
    }

    // MARK: - Lifecycle actions

    @discardableResult
    func kill(_ server: DevServer) async -> KillOutcome {
        let outcome = await KillStrategy.terminate(pid: server.pid)
        if outcome.didStopProcess {
            await engine.unmarkManaged(server.pid)
            if let root = server.managedRootPID {
                logService.discard(pid: root)
            }
        }
        Log.commands.info("Kill \(server.title, privacy: .public) [PID \(server.pid)] → \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    func killAll(_ servers: [DevServer]) async -> [KillOutcome] {
        var outcomes: [KillOutcome] = []
        for server in servers {
            outcomes.append(await kill(server))
        }
        return outcomes
    }

    /// Restarts a server by terminating it and relaunching its original argv in the
    /// same working directory. Environment variables can't be recovered for a
    /// process we didn't originally spawn, so the current environment is inherited
    /// (best-effort). Because DevDock owns the new process, live logs become available.
    @discardableResult
    func restart(_ server: DevServer) async -> Bool {
        guard server.canRestart,
              let cwd = server.workingDirectory,
              let executable = server.arguments.first,
              let resolved = CommandRunner.resolveExecutable(executable) else {
            return false
        }

        let outcome = await KillStrategy.terminate(pid: server.pid)
        // Only relaunch if the original process is confirmed gone — otherwise we'd
        // risk a duplicate process fighting for the same port.
        guard outcome.didStopProcess else {
            Log.commands.error("Restart aborted for \(server.pid): stop outcome \(String(describing: outcome), privacy: .public)")
            return false
        }

        if let root = server.managedRootPID {
            logService.discard(pid: root)
        }
        await engine.unmarkManaged(server.pid)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = Array(server.arguments.dropFirst())
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
        } catch {
            Log.commands.error("Restart failed for \(server.pid): \(error.localizedDescription, privacy: .public)")
            return false
        }

        let newPID = process.processIdentifier
        logService.register(process: process, pid: newPID)
        await engine.markManaged(newPID)
        Log.commands.info("Restarted \(server.title, privacy: .public) as PID \(newPID)")
        return true
    }
}
