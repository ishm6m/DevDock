import Darwin
import XCTest
@testable import DevDock

/// The scanner reads live kernel state rather than parsing text, so it is tested
/// against a socket this test binds itself: the strongest available check that the
/// libproc walk, the LISTEN filter, and the byte-order handling are all correct.
final class PortScannerTests: XCTestCase {

    private var descriptor: Int32 = -1

    override func tearDown() {
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
        super.tearDown()
    }

    /// Binds a listening TCP socket on a kernel-chosen loopback port.
    private func listen(family: Int32) throws -> Int {
        descriptor = socket(family, SOCK_STREAM, 0)
        try XCTSkipIf(descriptor < 0, "could not create socket")

        var port: UInt16 = 0
        if family == AF_INET {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = INADDR_ANY.bigEndian
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            try XCTSkipIf(bound != 0, "bind failed")
            var actual = sockaddr_in()
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &actual) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
            }
            port = UInt16(bigEndian: actual.sin_port)
        } else {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_addr = in6addr_loopback
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            try XCTSkipIf(bound != 0, "bind failed")
            var actual = sockaddr_in6()
            var size = socklen_t(MemoryLayout<sockaddr_in6>.size)
            _ = withUnsafeMutablePointer(to: &actual) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
            }
            port = UInt16(bigEndian: actual.sin6_port)
        }
        try XCTSkipIf(Darwin.listen(descriptor, 1) != 0, "listen failed")
        return Int(port)
    }

    func testFindsAnIPv4Listener() async throws {
        let port = try listen(family: AF_INET)
        let records = PortScanner.scan()
        let match = records.first { $0.pid == getpid() && $0.port == port }
        XCTAssertNotNil(match, "scanner missed a socket bound by this very process")
        XCTAssertEqual(match?.address, "*", "INADDR_ANY should surface as a wildcard bind")
        XCTAssertFalse(match?.command.isEmpty ?? true, "command name should be resolved")
    }

    func testFindsAnIPv6LoopbackListener() async throws {
        let port = try listen(family: AF_INET6)
        let records = PortScanner.scan()
        let match = records.first { $0.pid == getpid() && $0.port == port }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.address, "[::1]")
    }

    /// A connected-but-not-listening socket must not appear.
    func testIgnoresNonListeningSockets() async throws {
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        try XCTSkipIf(descriptor < 0, "could not create socket")
        let records = PortScanner.scan()
        XCTAssertFalse(records.contains { $0.pid == getpid() && $0.port == 0 })
    }
}
