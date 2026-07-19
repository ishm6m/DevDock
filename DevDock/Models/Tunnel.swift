import Foundation

/// A public tunnel (ngrok, Cloudflare Tunnel, LocalTunnel) exposing a local port.
struct Tunnel: Identifiable, Hashable {

    enum Kind: String, Codable {
        case ngrok
        case cloudflare
        case localtunnel

        var displayName: String {
            switch self {
            case .ngrok: return "ngrok"
            case .cloudflare: return "Cloudflare Tunnel"
            case .localtunnel: return "LocalTunnel"
            }
        }

        var symbol: String { "point.3.filled.connected.trianglepath.dotted" }
    }

    let kind: Kind
    let pid: Int32
    /// The public URL, when we can resolve it (e.g. via the ngrok local API).
    let publicURL: String?
    /// What the tunnel forwards to locally, e.g. `localhost:3000`.
    let forwardsTo: String?

    var id: String { "\(kind.rawValue)-\(pid)-\(publicURL ?? forwardsTo ?? "")" }

    var publicWebURL: URL? { publicURL.flatMap(URL.init(string:)) }
}
