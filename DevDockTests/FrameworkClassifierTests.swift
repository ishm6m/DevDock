import XCTest
@testable import DevDock

final class FrameworkClassifierTests: XCTestCase {

    private func classify(
        _ args: [String],
        exe: String? = nil,
        deps: Set<String> = [],
        python: String = "",
        markers: Set<ProjectInfo.Marker> = []
    ) -> Framework {
        FrameworkClassifier.classify(FrameworkSignals(
            arguments: args,
            executableBasename: exe,
            packageDependencies: deps,
            pythonManifest: python,
            projectMarkers: markers
        ))
    }

    // MARK: - CLI signals

    func testNextFromCLI() {
        XCTAssertEqual(classify(["node", "/app/node_modules/.bin/next", "dev"]), .nextjs)
    }

    func testViteFromCLI() {
        XCTAssertEqual(classify(["node", "/app/node_modules/.bin/vite"]), .vite)
    }

    func testAngularFromCLI() {
        XCTAssertEqual(classify(["node", "/app/node_modules/.bin/ng", "serve"]), .angular)
    }

    func testNuxtFromCLI() {
        XCTAssertEqual(classify(["node", "nuxi", "dev"]), .nuxt)
    }

    func testDjangoFromManageCommand() {
        XCTAssertEqual(classify(["python3", "manage.py", "runserver"]), .django)
    }

    func testFlaskFromCLI() {
        XCTAssertEqual(classify(["flask", "run"]), .flask)
    }

    func testFastAPIFromUvicorn() {
        XCTAssertEqual(classify(["uvicorn", "app.main:app", "--reload"]), .fastapi)
    }

    func testRailsFromCLI() {
        XCTAssertEqual(classify(["ruby", "bin/rails", "server"]), .rails)
    }

    func testLaravelFromArtisan() {
        XCTAssertEqual(classify(["php", "artisan", "serve"]), .laravel)
    }

    func testPHPBuiltInServer() {
        XCTAssertEqual(classify(["php", "-S", "localhost:8000"]), .php)
    }

    func testExpoFromCLI() {
        XCTAssertEqual(classify(["node", "expo", "start"]), .expo)
    }

    func testMetroFromReactNative() {
        XCTAssertEqual(classify(["node", "react-native", "start"]), .metro)
    }

    // MARK: - package.json dependency signals

    func testExpressFromDependencies() {
        XCTAssertEqual(classify(["node", "server.js"], deps: ["express"]), .express)
    }

    func testReactFromDependencies() {
        XCTAssertEqual(classify(["node", "start.js"], deps: ["react", "react-dom"]), .react)
    }

    func testNextWinsOverExpressInDependencies() {
        XCTAssertEqual(classify(["node", "run.js"], deps: ["next", "express"]), .nextjs)
    }

    func testRemixFromScopedDependency() {
        XCTAssertEqual(classify(["node", "server.js"], deps: ["@remix-run/node"]), .remix)
    }

    func testNestFromDependency() {
        XCTAssertEqual(classify(["node", "dist/main.js"], deps: ["@nestjs/core"]), .nestjs)
    }

    // MARK: - Python manifest signals

    func testDjangoFromManifest() {
        XCTAssertEqual(classify(["python3", "app.py"], python: "django==4.2\n"), .django)
    }

    func testFastAPIFromManifest() {
        XCTAssertEqual(classify(["python3", "app.py"], python: "fastapi\nuvicorn\n"), .fastapi)
    }

    // MARK: - Runtime + marker fallbacks

    func testBunRuntime() {
        XCTAssertEqual(classify(["bun", "index.ts"], exe: "bun"), .bun)
    }

    func testDenoRuntime() {
        XCTAssertEqual(classify(["deno", "run", "-A", "main.ts"], exe: "deno"), .deno)
    }

    func testGoFromMarker() {
        XCTAssertEqual(classify(["/tmp/exe/server"], exe: "server", markers: [.goMod]), .go)
    }

    func testRustFromMarker() {
        XCTAssertEqual(classify(["/target/debug/api"], exe: "api", markers: [.cargoToml]), .rust)
    }

    func testNodeRuntimeFallback() {
        XCTAssertEqual(classify(["node", "index.js"], exe: "node"), .node)
    }

    func testUnknownWhenNoSignals() {
        XCTAssertEqual(classify(["/opt/some/mystery-binary"], exe: "mystery-binary"), .unknown)
    }
}
