import Foundation

/// Detects and controls Docker containers via the `docker` CLI.
///
/// When Docker isn't installed or the daemon isn't running, `containers()` returns
/// an empty list and the UI simply hides the Docker section — graceful degradation
/// rather than an error state.
final class DockerService: @unchecked Sendable {

    private let runner: CommandRunner

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func isAvailable() -> Bool {
        CommandRunner.resolveExecutable("docker") != nil
    }

    func containers() async -> [DockerContainer] {
        guard isAvailable() else { return [] }
        // One JSON object per line keeps parsing robust across docker versions.
        let result = await runner.run("docker", arguments: ["ps", "--no-trunc", "--format", "{{json .}}"])
        guard result.succeeded else { return [] }
        return Self.parse(result.standardOutput)
    }

    func stop(id: String) async -> Bool {
        await runner.run("docker", arguments: ["stop", id]).succeeded
    }

    func restart(id: String) async -> Bool {
        await runner.run("docker", arguments: ["restart", id]).succeeded
    }

    /// Parses `docker ps --format '{{json .}}'` output (newline-delimited JSON).
    static func parse(_ output: String) -> [DockerContainer] {
        var containers: [DockerContainer] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let portsRaw = (object["Ports"] as? String) ?? ""
            let ports = portsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            containers.append(DockerContainer(
                id: (object["ID"] as? String) ?? UUID().uuidString,
                name: (object["Names"] as? String) ?? "container",
                image: (object["Image"] as? String) ?? "",
                state: (object["State"] as? String) ?? "",
                status: (object["Status"] as? String) ?? "",
                ports: ports
            ))
        }
        return containers.sorted { $0.name < $1.name }
    }
}
