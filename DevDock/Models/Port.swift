import Foundation

/// A TCP port a process is listening on, as discovered by `PortScanner`.
struct Port: Hashable, Codable {
    let number: Int
    /// The bound address as reported by lsof, e.g. `127.0.0.1`, `*`, `[::1]`.
    let address: String
    /// Transport protocol; currently always `TCP`.
    let networkProtocol: String

    init(number: Int, address: String, networkProtocol: String = "TCP") {
        self.number = number
        self.address = address
        self.networkProtocol = networkProtocol
    }

    /// True when the port is reachable on the local machine (loopback or wildcard),
    /// which is what makes it a candidate dev server rather than a remote socket.
    var isLocallyReachable: Bool {
        address == "*" || address.hasPrefix("127.") || address.contains("::1") || address == "0.0.0.0" || address == "[::]"
    }

    /// The URL a developer would open in the browser.
    var localURL: URL {
        URL(string: "http://localhost:\(number)") ?? URL(fileURLWithPath: "/")
    }

    var displayString: String { "localhost:\(number)" }
}
