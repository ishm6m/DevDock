import Foundation

/// A Docker container as reported by `docker ps`.
struct DockerContainer: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    /// High-level state, e.g. `running`, `exited`, `paused`.
    let state: String
    /// Human status string, e.g. `Up 2 hours`.
    let status: String
    /// Raw published-port mappings, e.g. `0.0.0.0:5432->5432/tcp`.
    let ports: [String]

    var isRunning: Bool { state.lowercased() == "running" }

    /// The first HTTP-reachable published host port, if any, for the "Open" action.
    var primaryURL: URL? {
        for mapping in ports {
            // Formats: "0.0.0.0:8080->80/tcp" or ":::8080->80/tcp"
            guard let hostSide = mapping.components(separatedBy: "->").first else { continue }
            guard let portString = hostSide.components(separatedBy: ":").last,
                  let hostPort = Int(portString) else { continue }
            return URL(string: "http://localhost:\(hostPort)")
        }
        return nil
    }
}
