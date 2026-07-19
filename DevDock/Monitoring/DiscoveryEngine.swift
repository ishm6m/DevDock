import Foundation

/// An immutable result of one discovery pass, produced off the main thread.
struct DiscoverySnapshot {
    var servers: [DevServer]
    var databases: [DatabaseService]
    var containers: [DockerContainer]
    var tunnels: [Tunnel]
    var conflictPorts: Set<Int>
}

/// The off-main engine that performs a full discovery pass and returns a snapshot.
///
/// Being an `actor` gives it a single-threaded execution domain, so its caches
/// (static per-PID metadata and the CPU sampler) are inherently safe. Static
/// metadata — project root, git, framework, argv, launch time — is computed once
/// per PID and reused; only resource usage is recomputed each cycle, which is what
/// keeps refreshes cheap.
actor DiscoveryEngine {

    private let portScanner: PortScanner
    private let processMonitor: ProcessMonitor
    private let frameworkDetector: FrameworkDetector
    private let projectLocator: ProjectLocator
    private let gitService: GitService
    private let databaseDetector: DatabaseDetector
    private let dockerService: DockerService
    private let tunnelDetector: TunnelDetector

    private var staticCache: [Int32: StaticInfo] = [:]
    private var managedPIDs: Set<Int32> = []

    /// Command-name fragments that are never dev servers: macOS daemons, Docker
    /// plumbing, and — importantly — editor/browser "helper" processes, which each
    /// listen on a loopback port and would otherwise drown out real servers. Matched
    /// case-insensitively as substrings, so "helper" catches "Code Helper (Plugin)".
    private static let systemDenylist: [String] = [
        // macOS daemons
        "rapportd", "controlce", "controlcenter", "sharingd", "identityservicesd",
        "remoted", "airplayxpchelper", "sshd", "cupsd", "mdnsresponder", "netbiosd",
        "rpcbind",
        // Docker host plumbing (containers appear in their own section)
        "com.docker", "docker", "dockerd", "vpnkit",
        // Editor / browser / desktop-app helper processes
        "helper", "electron",
        "google chrome", "chromium", "firefox", "safari", "brave", "microsoft edge", "arc",
        "slack", "discord", "spotify", "notion", "zoom",
    ]

    /// Command names surfaced in the Tunnels section instead of the server list.
    private static let tunnelNames: Set<String> = ["ngrok", "cloudflared", "lt"]

    private struct StaticInfo {
        let arguments: [String]
        let executablePath: String?
        let workingDirectory: String?
        let project: ProjectInfo?
        let git: GitInfo?
        let framework: Framework
        let launchDate: Date
        let commandName: String
    }

    init(
        portScanner: PortScanner,
        processMonitor: ProcessMonitor,
        frameworkDetector: FrameworkDetector,
        projectLocator: ProjectLocator,
        gitService: GitService,
        databaseDetector: DatabaseDetector,
        dockerService: DockerService,
        tunnelDetector: TunnelDetector
    ) {
        self.portScanner = portScanner
        self.processMonitor = processMonitor
        self.frameworkDetector = frameworkDetector
        self.projectLocator = projectLocator
        self.gitService = gitService
        self.databaseDetector = databaseDetector
        self.dockerService = dockerService
        self.tunnelDetector = tunnelDetector
    }

    /// Records that DevDock launched a process, so it (and its descendants) are
    /// treated as managed — enabling reliable restart and live logs.
    func markManaged(_ pid: Int32) { managedPIDs.insert(pid) }

    func unmarkManaged(_ pid: Int32) {
        managedPIDs.remove(pid)
        staticCache[pid] = nil
    }

    // MARK: - Discovery

    func discover(preferences: Preferences) async -> DiscoverySnapshot {
        let records = await portScanner.scan()
        let now = Date()

        let databases = preferences.monitorDatabases ? databaseDetector.detect(from: records) : []
        let databasePorts = Set(databases.map(\.port))

        let conflictPorts = Self.conflictPorts(in: records)

        var servers: [DevServer] = []
        var seenKeys: Set<String> = []
        var activePIDs: Set<Int32> = []

        for record in records {
            guard isDevServerCandidate(record) else { continue }
            guard !databasePorts.contains(record.port) else { continue }

            let key = "\(record.pid)-\(record.port)"
            guard seenKeys.insert(key).inserted else { continue }

            guard let metrics = processMonitor.metrics(for: record.pid, now: now) else { continue }
            activePIDs.insert(record.pid)

            let info = staticInfo(for: record.pid, snapshot: metrics.snapshot, port: record.port)

            let commandString = info.arguments.isEmpty
                ? (record.command.isEmpty ? info.commandName : record.command)
                : info.arguments.joined(separator: " ")

            servers.append(DevServer(
                pid: record.pid,
                port: Port(number: record.port, address: record.address),
                command: commandString,
                executablePath: info.executablePath,
                arguments: info.arguments,
                framework: info.framework,
                workingDirectory: info.workingDirectory,
                project: info.project,
                git: info.git,
                resources: metrics.usage,
                launchDate: info.launchDate,
                managedRootPID: managedRootPID(for: record.pid),
                hasPortConflict: conflictPorts.contains(record.port)
            ))
        }

        pruneCaches(activePIDs: activePIDs)

        servers.sort { lhs, rhs in
            let l = lhs.title.lowercased(), r = rhs.title.lowercased()
            return l == r ? lhs.port.number < rhs.port.number : l < r
        }

        let containers = preferences.monitorDocker ? await dockerService.containers() : []
        let tunnels = preferences.monitorTunnels ? await tunnelDetector.detect() : []

        return DiscoverySnapshot(
            servers: servers,
            databases: databases,
            containers: containers,
            tunnels: tunnels,
            conflictPorts: conflictPorts
        )
    }

    // MARK: - Helpers

    private func staticInfo(for pid: Int32, snapshot: Proc.Snapshot, port: Int) -> StaticInfo {
        if let cached = staticCache[pid] { return cached }

        let project = projectLocator.locate(fromWorkingDirectory: snapshot.workingDirectory)
        let git = gitService.info(forProjectRoot: project?.rootPath)
        let framework = frameworkDetector.detect(
            arguments: snapshot.arguments,
            executablePath: snapshot.executablePath,
            project: project,
            port: port
        )
        let info = StaticInfo(
            arguments: snapshot.arguments,
            executablePath: snapshot.executablePath,
            workingDirectory: snapshot.workingDirectory,
            project: project,
            git: git,
            framework: framework,
            launchDate: snapshot.startTime,
            commandName: snapshot.name
        )
        staticCache[pid] = info
        return info
    }

    /// Walks the parent chain to see whether this PID descends from a process
    /// DevDock launched; returns that ancestor's PID for log lookup.
    private func managedRootPID(for pid: Int32) -> Int32? {
        var current: Int32? = pid
        var hops = 0
        while let value = current, hops < 20 {
            if managedPIDs.contains(value) { return value }
            let parent = Proc.parentPID(value)
            if parent == nil || parent == value || parent == 0 { break }
            current = parent
            hops += 1
        }
        return nil
    }

    private func pruneCaches(activePIDs: Set<Int32>) {
        processMonitor.prune(keeping: activePIDs)
        staticCache = staticCache.filter { activePIDs.contains($0.key) || managedPIDs.contains($0.key) }
        managedPIDs = managedPIDs.filter { Proc.isAlive($0) }
    }

    private func isDevServerCandidate(_ record: PortScanRecord) -> Bool {
        guard Self.isLocallyReachable(record.address) else { return false }
        let name = record.command.lowercased()
        if Self.tunnelNames.contains(name) { return false }
        if Self.systemDenylist.contains(where: { name.contains($0) }) { return false }
        return true
    }

    private static func isLocallyReachable(_ address: String) -> Bool {
        address == "*" || address == "0.0.0.0" || address == "[::]"
            || address.hasPrefix("127.") || address.contains("::1")
    }

    private static func conflictPorts(in records: [PortScanRecord]) -> Set<Int> {
        var pidsByPort: [Int: Set<Int32>] = [:]
        for record in records where isLocallyReachable(record.address) {
            pidsByPort[record.port, default: []].insert(record.pid)
        }
        return Set(pidsByPort.filter { $0.value.count > 1 }.keys)
    }
}
