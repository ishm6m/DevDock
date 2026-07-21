import Foundation

/// The dependency-injection container.
///
/// Everything is constructed once here and passed down explicitly, so there are no
/// global singletons. Swapping a concrete service for a test double is a one-line
/// change in this file (or via a dedicated test initializer).
@MainActor
final class AppEnvironment {

    let preferencesStore: PreferencesStore
    let favoritesStore: FavoritesStore
    let logService: LogService
    let notificationManager: NotificationManager
    let dockerService: DockerService
    let engine: DiscoveryEngine
    let coordinator: DiscoveryCoordinator
    let commands: ServerCommands
    let autoStop: AutoStopController
    let updater: any UpdateChecking

    init() {
        let runner = CommandRunner()
        let preferencesStore = PreferencesStore()
        let favoritesStore = FavoritesStore()
        let logService = LogService()
        let notificationManager = NotificationManager()
        let dockerService = DockerService(runner: runner)

        let engine = DiscoveryEngine(
            portScanner: PortScanner(),
            processMonitor: ProcessMonitor(),
            frameworkDetector: FrameworkDetector(),
            projectLocator: ProjectLocator(),
            gitService: GitService(),
            databaseDetector: DatabaseDetector(),
            dockerService: dockerService,
            tunnelDetector: TunnelDetector()
        )

        self.preferencesStore = preferencesStore
        self.favoritesStore = favoritesStore
        self.logService = logService
        self.notificationManager = notificationManager
        self.dockerService = dockerService
        self.engine = engine

        // Build commands + auto-stop before the coordinator, which drives auto-stop each
        // refresh pass.
        let commands = ServerCommands(engine: engine, logService: logService)
        let autoStop = AutoStopController(
            commands: commands,
            favorites: favoritesStore,
            notifications: notificationManager,
            preferencesStore: preferencesStore
        )
        self.commands = commands
        self.autoStop = autoStop
        self.coordinator = DiscoveryCoordinator(
            engine: engine,
            notifications: notificationManager,
            preferencesStore: preferencesStore,
            autoStop: autoStop
        )
        self.updater = SparkleUpdater()
    }
}
