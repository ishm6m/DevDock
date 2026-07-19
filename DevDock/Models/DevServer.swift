import Foundation

/// The central domain model: a single discovered development server.
///
/// A server is uniquely identified by its PID + port, so a process listening on
/// multiple ports appears as multiple rows (which matches how developers think
/// about "localhost:3000" vs "localhost:3001").
struct DevServer: Identifiable, Hashable {
    let pid: Int32
    let port: Port
    let command: String
    let executablePath: String?
    let arguments: [String]
    let framework: Framework
    let workingDirectory: String?
    let project: ProjectInfo?
    let git: GitInfo?
    var resources: ResourceUsage
    let launchDate: Date

    /// The PID whose captured pipes back this server's live logs, if DevDock started
    /// it. This is the launched process itself or an ancestor DevDock launched (so a
    /// `npm run dev` wrapper's logs still surface for the child that binds the port).
    var managedRootPID: Int32?

    /// True when more than one process is bound to this port.
    var hasPortConflict: Bool

    /// Why this server is flagged as needing attention (forgotten / high CPU), computed
    /// each refresh by the `DiscoveryCoordinator`. Defaults to no attention needed.
    var attention: ServerAttention = .none

    /// True when DevDock started (or restarted) this process, so we own its
    /// stdout/stderr pipes (live logs available) and can restart it reliably.
    var isManaged: Bool { managedRootPID != nil }

    var id: String { "\(pid)-\(port.number)" }

    var localURL: URL { port.localURL }

    /// The best human-facing title for the row.
    var title: String {
        if let name = project?.name, !name.isEmpty { return name }
        if framework != .unknown { return framework.displayName }
        return command.split(separator: " ").first.map(String.init) ?? "Process"
    }

    /// Restart is only reliable when we can reconstruct the invocation and directory.
    var canRestart: Bool {
        !arguments.isEmpty && (workingDirectory != nil)
    }

    var runningDuration: String { Formatters.duration(since: launchDate) }
}
