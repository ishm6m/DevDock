import OSLog

/// Centralized `os.Logger` instances, grouped by subsystem area.
///
/// Using unified logging keeps diagnostics out of stdout and lets us inspect
/// DevDock's behavior in Console.app without shipping a custom logging stack.
enum Log {
    private static let subsystem = "com.devdock.DevDock"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let commands = Logger(subsystem: subsystem, category: "commands")
    static let docker = Logger(subsystem: subsystem, category: "docker")
    static let logs = Logger(subsystem: subsystem, category: "logs")
}
