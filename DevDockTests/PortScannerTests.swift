import XCTest
@testable import DevDock

final class PortScannerTests: XCTestCase {

    func testParsesMultipleProcesses() {
        let output = """
        p1234
        cnode
        n*:3000
        p5678
        cpostgres
        n127.0.0.1:5432
        p9999
        credis-server
        n[::1]:6379
        """
        let records = PortScanner.parse(output)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0], PortScanRecord(pid: 1234, command: "node", port: 3000, address: "*"))
        XCTAssertEqual(records[1], PortScanRecord(pid: 5678, command: "postgres", port: 5432, address: "127.0.0.1"))
        XCTAssertEqual(records[2], PortScanRecord(pid: 9999, command: "redis-server", port: 6379, address: "[::1]"))
    }

    func testMultiplePortsForOneProcess() {
        let output = """
        p42
        cnode
        n*:3000
        n*:3001
        """
        let records = PortScanner.parse(output)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.pid == 42 && $0.command == "node" })
        XCTAssertEqual(Set(records.map(\.port)), [3000, 3001])
    }

    func testIgnoresUnparseableNames() {
        let output = """
        p1
        cnode
        nsome-garbage-without-port
        """
        XCTAssertTrue(PortScanner.parse(output).isEmpty)
    }

    func testParseAddressIPv4() {
        let parsed = PortScanner.parseAddress("127.0.0.1:8080")
        XCTAssertEqual(parsed?.address, "127.0.0.1")
        XCTAssertEqual(parsed?.port, 8080)
    }

    func testParseAddressIPv6UsesLastColon() {
        let parsed = PortScanner.parseAddress("[::1]:6379")
        XCTAssertEqual(parsed?.address, "[::1]")
        XCTAssertEqual(parsed?.port, 6379)
    }

    func testParseAddressWildcard() {
        let parsed = PortScanner.parseAddress("*:3000")
        XCTAssertEqual(parsed?.address, "*")
        XCTAssertEqual(parsed?.port, 3000)
    }
}
