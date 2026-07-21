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

    /// Docker and tunnel probes are expensive relative to the port scan — `docker ps`
    /// forks a process and talks to the daemon (~120ms), and tunnel detection names
    /// every PID on the system. Both describe things that change on human timescales,
    /// so they are re-probed at most this often rather than once per refresh — and only
    /// while the panel is open, since both feed panel-only sections (`probeAuxiliary`).
    private static let auxiliaryProbeInterval: TimeInterval = 5
    private var cachedContainers: (value: [DockerContainer], at: Date)?
    private var cachedTunnels: (value: [Tunnel], at: Date)?

    /// Command names that are never dev servers: macOS daemons, Docker plumbing, and
    /// desktop apps that each listen on a loopback port and would otherwise drown out
    /// real servers.
    ///
    /// Matched *exactly* against the lowercased command name. `lsof +c 0` reports the
    /// full executable basename, so exact is sufficient — and substring matching was
    /// actively wrong: `contains("arc")` also swallowed `search-server`, `marcy`, and
    /// anything else with those three letters anywhere in its name.
    static let denylistNames: Set<String> = [
        // macOS daemons
        "rapportd", "controlce", "controlcenter", "sharingd", "identityservicesd",
        "remoted", "airplayxpchelper", "sshd", "cupsd", "mdnsresponder", "netbiosd",
        "rpcbind",
        // Docker host plumbing (containers appear in their own section)
        "docker", "dockerd", "vpnkit",
        // Desktop apps
        "arc", "safari", "firefox", "chromium", "google chrome", "brave browser",
        "microsoft edge", "slack", "discord", "spotify", "notion", "zoom", "zoom.us",
    ]

    /// Denied when they appear as a whole *word* in the command name. Desktop apps
    /// spawn a swarm of helpers — "Google Chrome Helper (Renderer)", "Slack Helper" —
    /// whose names can't be enumerated, but a word match still can't hit `helperton`.
    static let denylistWords: Set<String> = ["helper", "electron"]

    /// True for command names that should never appear as a dev server.
    static func isDenied(_ lowercasedName: String) -> Bool {
        if denylistNames.contains(lowercasedName) { return true }
        // A real reverse-DNS namespace, so a prefix here can't over-match: this is
        // com.docker.backend, com.docker.extensions, and friends.
        if lowercasedName.hasPrefix("com.docker") { return true }
        return lowercasedName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { denylistWords.contains(String($0)) }
    }

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

    /// Forces the next pass to re-probe Docker, bypassing `auxiliaryProbeInterval`.
    /// Called after the user stops or restarts a container so the panel reflects the
    /// action immediately instead of up to five seconds later.
    func invalidateDockerCache() { cachedContainers = nil }

    // MARK: - Discovery

    /// - Parameter probeAuxiliary: whether to re-probe Docker and tunnels. Both feed
    ///   panel-only sections, so the caller passes `false` while the panel is closed and
    ///   the last known values are reused — see `containers(now:probe:)`.
    func discover(preferences: Preferences, probeAuxiliary: Bool = true) async -> DiscoverySnapshot {
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

            guard let usage = processMonitor.usage(for: record.pid, now: now) else { continue }
            activePIDs.insert(record.pid)

            guard let info = staticInfo(for: record.pid, port: record.port) else { continue }

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
                resources: usage,
                launchDate: info.launchDate,
                managedRootPID: managedRootPID(for: record.pid),
                hasPortConflict: conflictPorts.contains(record.port)
            ))
        }

        pruneCaches(activePIDs: activePIDs)

        // Decorate-sort-undecorate: `title` is a computed string and lowercasing it inside
        // the comparator rebuilt it O(n log n) times. Build each key once instead.
        var keyed: [(key: String, server: DevServer)] = servers.map { ($0.title.lowercased(), $0) }
        keyed.sort { lhs, rhs in
            lhs.key == rhs.key ? lhs.server.port.number < rhs.server.port.number : lhs.key < rhs.key
        }
        servers = keyed.map(\.server)

        let containers = preferences.monitorDocker ? await containers(now: now, probe: probeAuxiliary) : []
        let tunnels = preferences.monitorTunnels ? await tunnels(now: now, probe: probeAuxiliary) : []

        return DiscoverySnapshot(
            servers: servers,
            databases: databases,
            containers: containers,
            tunnels: tunnels,
            conflictPorts: conflictPorts
        )
    }

    // MARK: - Throttled auxiliary probes

    private func containers(now: Date, probe: Bool) async -> [DockerContainer] {
        if let cached = cachedContainers,
           !probe || now.timeIntervalSince(cached.at) < Self.auxiliaryProbeInterval {
            return cached.value
        }
        guard probe else { return [] }
        let value = await dockerService.containers()
        cachedContainers = (value, now)
        return value
    }

    private func tunnels(now: Date, probe: Bool) async -> [Tunnel] {
        if let cached = cachedTunnels,
           !probe || now.timeIntervalSince(cached.at) < Self.auxiliaryProbeInterval {
            return cached.value
        }
        guard probe else { return [] }
        let value = await tunnelDetector.detect()
        cachedTunnels = (value, now)
        return value
    }

    // MARK: - Helpers

    /// The per-PID metadata that never changes while the process lives. The expensive
    /// kernel reads (argv, exec path, cwd) happen here, on a cache miss only — never on
    /// the per-refresh path.
    private func staticInfo(for pid: Int32, port: Int) -> StaticInfo? {
        if let cached = staticCache[pid] { return cached }
        guard let snapshot = Proc.snapshot(pid) else { return nil }

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
        if Self.isDenied(name) { return false }
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
