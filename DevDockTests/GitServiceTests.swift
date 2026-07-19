import XCTest
@testable import DevDock

final class GitServiceTests: XCTestCase {

    func testRepositoryNameFromSSHRemote() {
        XCTAssertEqual(GitService.repositoryName(fromRemoteURL: "git@github.com:acme/widgets.git"), "widgets")
    }

    func testRepositoryNameFromHTTPSRemote() {
        XCTAssertEqual(GitService.repositoryName(fromRemoteURL: "https://github.com/acme/widgets.git"), "widgets")
    }

    func testRepositoryNameWithoutGitSuffix() {
        XCTAssertEqual(GitService.repositoryName(fromRemoteURL: "https://gitlab.com/team/api"), "api")
    }

    func testFirstRemoteURLFromConfig() {
        let config = """
        [core]
            repositoryformatversion = 0
        [remote "origin"]
            url = git@github.com:acme/widgets.git
            fetch = +refs/heads/*:refs/remotes/origin/*
        """
        XCTAssertEqual(GitService.firstRemoteURL(inConfig: config), "git@github.com:acme/widgets.git")
    }

    func testBranchFromHead() throws {
        let dir = try makeTempGitDir(headContents: "ref: refs/heads/feature/login\n")
        XCTAssertEqual(GitService.branch(gitDirectory: dir), "feature/login")
    }

    func testDetachedHeadReturnsShortSHA() throws {
        let dir = try makeTempGitDir(headContents: "3f1a2b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a\n")
        XCTAssertEqual(GitService.branch(gitDirectory: dir), "3f1a2b9")
    }

    // MARK: - Helpers

    private func makeTempGitDir(headContents: String) throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try headContents.write(to: base.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: base.deletingLastPathComponent()) }
        return base.path
    }
}
