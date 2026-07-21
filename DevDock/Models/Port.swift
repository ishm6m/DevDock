import Foundation

/// A TCP port a process is listening on, as discovered by `PortScanner`.
struct Port: Hashable, Codable {
    let number: Int
    /// The bound local address, e.g. `127.0.0.1`, `*`, `[::1]`.
    let address: String

    /// The URL a developer would open in the browser.
    var localURL: URL {
        URL(string: "http://localhost:\(number)") ?? URL(fileURLWithPath: "/")
    }

    var displayString: String { "localhost:\(number)" }
}
