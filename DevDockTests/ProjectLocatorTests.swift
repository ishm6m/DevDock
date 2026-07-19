import XCTest
@testable import DevDock

final class ProjectLocatorTests: XCTestCase {

    private let fileManager = FileManager.default
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? fileManager.removeItem(at: root) }
        roots.removeAll()
    }

    private func makeTree(marker: String, nestedSubpath: String) throws -> (root: URL, workingDir: URL) {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // Create the marker (file or directory).
        if marker == ".git" {
            try fileManager.createDirectory(at: root.appendingPathComponent(marker), withIntermediateDirectories: true)
        } else {
            try "{}".write(to: root.appendingPathComponent(marker), atomically: true, encoding: .utf8)
        }
        let workingDir = root.appendingPathComponent(nestedSubpath)
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
        return (root, workingDir)
    }

    func testLocatesPackageJSONFromNestedDirectory() throws {
        let (root, workingDir) = try makeTree(marker: "package.json", nestedSubpath: "src/components")
        let locator = ProjectLocator()
        let info = locator.locate(fromWorkingDirectory: workingDir.path)
        XCTAssertEqual(info?.rootPath, root.standardizedFileURL.path)
        XCTAssertEqual(info?.marker, .packageJSON)
    }

    func testLocatesGitRoot() throws {
        let (root, workingDir) = try makeTree(marker: ".git", nestedSubpath: "cmd/server")
        let info = ProjectLocator().locate(fromWorkingDirectory: workingDir.path)
        XCTAssertEqual(info?.rootPath, root.standardizedFileURL.path)
        XCTAssertEqual(info?.marker, .git)
    }

    func testPackageJSONWinsOverGitInSameDirectory() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        try fileManager.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let info = ProjectLocator().locate(fromWorkingDirectory: root.path)
        XCTAssertEqual(info?.marker, .packageJSON)
    }

    func testReturnsNilWhenNoMarker() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        roots.append(root)
        let workingDir = root.appendingPathComponent("empty/child")
        try fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)

        // Limit depth so the walk can't reach any real markers higher on disk.
        let locator = ProjectLocator(maxDepth: 2)
        XCTAssertNil(locator.locate(fromWorkingDirectory: workingDir.path))
    }

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(ProjectLocator().locate(fromWorkingDirectory: nil))
        XCTAssertNil(ProjectLocator().locate(fromWorkingDirectory: ""))
    }
}
