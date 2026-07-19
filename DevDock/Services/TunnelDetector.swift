import Foundation

/// Detects public tunnels exposing local ports.
///
/// - ngrok exposes a local REST API on `127.0.0.1:4040`, which gives us exact
///   public URLs and forwarding targets.
/// - Cloudflare Tunnel (`cloudflared`) and LocalTunnel (`lt`) are detected by
///   process name. Their public URLs are only printed to their own output, so we
///   surface their presence without a URL (best-effort, as documented).
final class TunnelDetector: @unchecked Sendable {

    private let session: URLSession

    init(session: URLSession = TunnelDetector.makeSession()) {
        self.session = session
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.0
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func detect() async -> [Tunnel] {
        let named = Self.enumerateNamedProcesses()
        var tunnels = await ngrokTunnels(named: named)
        tunnels += processTunnels(named: named)

        var seen: Set<String> = []
        return tunnels.filter { seen.insert($0.id).inserted }
    }

    // MARK: - ngrok

    private func ngrokTunnels(named: [(pid: Int32, name: String)]) async -> [Tunnel] {
        guard let url = URL(string: "http://127.0.0.1:4040/api/tunnels") else { return [] }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["tunnels"] as? [[String: Any]] else {
            return []
        }

        let pid = named.first(where: { $0.name == "ngrok" })?.pid ?? 0
        return entries.map { entry in
            let publicURL = entry["public_url"] as? String
            let forwardsTo = (entry["config"] as? [String: Any])?["addr"] as? String
            return Tunnel(kind: .ngrok, pid: pid, publicURL: publicURL, forwardsTo: forwardsTo)
        }
    }

    // MARK: - Process-based detection

    private func processTunnels(named: [(pid: Int32, name: String)]) -> [Tunnel] {
        var tunnels: [Tunnel] = []
        for entry in named {
            switch entry.name {
            case "cloudflared":
                tunnels.append(Tunnel(kind: .cloudflare, pid: entry.pid, publicURL: nil, forwardsTo: nil))
            case "lt", "localtunnel":
                tunnels.append(Tunnel(kind: .localtunnel, pid: entry.pid, publicURL: nil, forwardsTo: nil))
            default:
                break
            }
        }
        return tunnels
    }

    /// Enumerates all processes with their lowercased names in a single pass.
    private static func enumerateNamedProcesses() -> [(pid: Int32, name: String)] {
        Proc.allPIDs().compactMap { pid in
            guard let name = Proc.name(pid)?.lowercased() else { return nil }
            return (pid, name)
        }
    }
}
