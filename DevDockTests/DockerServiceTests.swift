import XCTest
@testable import DevDock

final class DockerServiceTests: XCTestCase {

    func testParsesContainers() {
        let output = """
        {"ID":"abc123","Names":"postgres","Image":"postgres:16","State":"running","Status":"Up 2 hours","Ports":"0.0.0.0:5432->5432/tcp"}
        {"ID":"def456","Names":"cache","Image":"redis:7","State":"running","Status":"Up 5 minutes","Ports":"0.0.0.0:6379->6379/tcp, :::6379->6379/tcp"}
        """
        let containers = DockerService.parse(output)
        XCTAssertEqual(containers.count, 2)

        let postgres = try? XCTUnwrap(containers.first { $0.name == "postgres" })
        XCTAssertEqual(postgres?.image, "postgres:16")
        XCTAssertTrue(postgres?.isRunning == true)
        XCTAssertEqual(postgres?.primaryURL, URL(string: "http://localhost:5432"))

        let cache = containers.first { $0.name == "cache" }
        XCTAssertEqual(cache?.ports.count, 2)
    }

    func testIgnoresMalformedLines() {
        let output = """
        not-json
        {"ID":"ok","Names":"web","Image":"nginx","State":"running","Status":"Up","Ports":""}
        """
        let containers = DockerService.parse(output)
        XCTAssertEqual(containers.count, 1)
        XCTAssertEqual(containers.first?.name, "web")
        XCTAssertNil(containers.first?.primaryURL)
    }
}
