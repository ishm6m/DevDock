import XCTest
@testable import DevDock

/// The denylist used to match substrings, which silently swallowed any process whose
/// name merely *contained* a listed fragment. These pin the new whole-word behaviour.
final class DenylistTests: XCTestCase {

    func testDeniesExactSystemNames() {
        for name in ["rapportd", "sshd", "mdnsresponder", "docker", "dockerd", "arc", "google chrome"] {
            XCTAssertTrue(DiscoveryEngine.isDenied(name), "\(name) should be denied")
        }
    }

    func testDeniesDockerNamespace() {
        XCTAssertTrue(DiscoveryEngine.isDenied("com.docker.backend"))
        XCTAssertTrue(DiscoveryEngine.isDenied("com.docker.extensions"))
    }

    func testDeniesHelperProcessesByWord() {
        XCTAssertTrue(DiscoveryEngine.isDenied("google chrome helper (renderer)"))
        XCTAssertTrue(DiscoveryEngine.isDenied("code helper (plugin)"))
        XCTAssertTrue(DiscoveryEngine.isDenied("electron"))
    }

    /// The regression that motivated this: substring matching killed anything with
    /// "arc", "docker", "zoom", or "helper" buried inside its name.
    func testAllowsLegitimateServers() {
        for name in [
            "node", "python3", "ruby", "cargo", "vite", "next-server",
            "arcade-server",     // contained "arc"
            "search-service",    // contained "arc"
            "marcy",             // contained "arc"
            "dockerize",         // contained "docker"
            "helperton",         // contained "helper"
            "zoombie",           // contained "zoom"
            "electrondev",       // contained "electron"
        ] {
            XCTAssertFalse(DiscoveryEngine.isDenied(name), "\(name) should NOT be denied")
        }
    }
}
