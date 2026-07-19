import Foundation

/// Reads git metadata directly from the `.git` directory.
///
/// DevDock never shells out to `git`: the current branch comes from `.git/HEAD`
/// and the repository name from the `origin` remote in `.git/config` (falling back
/// to the directory name). This is fast, dependency-free, and safe.
final class GitService: @unchecked Sendable {

    func info(forProjectRoot root: String?) -> GitInfo? {
        guard let root else { return nil }
        let gitPath = (root as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitPath) else { return nil }

        let branch = Self.branch(gitDirectory: gitPath)
        let repository = Self.repositoryName(root: root, gitDirectory: gitPath)
        if branch == nil && repository == nil { return nil }
        return GitInfo(repositoryName: repository, branch: branch)
    }

    /// Parses `.git/HEAD`. A symbolic ref yields the branch name; a detached HEAD
    /// yields the short commit SHA.
    static func branch(gitDirectory: String) -> String? {
        let headPath = (gitDirectory as NSString).appendingPathComponent("HEAD")
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = trimmed.range(of: "refs/heads/") {
            return String(trimmed[range.upperBound...])
        }
        if trimmed.hasPrefix("ref:") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7)) // detached HEAD
    }

    static func repositoryName(root: String, gitDirectory: String) -> String? {
        let configPath = (gitDirectory as NSString).appendingPathComponent("config")
        if let content = try? String(contentsOfFile: configPath, encoding: .utf8),
           let remote = firstRemoteURL(inConfig: content),
           let name = repositoryName(fromRemoteURL: remote) {
            return name
        }
        // Fall back to the project directory name.
        let dirName = (root as NSString).lastPathComponent
        return dirName.isEmpty ? nil : dirName
    }

    /// Extracts the first `url = …` value from a git config file.
    static func firstRemoteURL(inConfig content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("url") else { continue }
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let value = trimmed[trimmed.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Derives a repo name from either SSH (`git@host:owner/repo.git`) or HTTPS
    /// (`https://host/owner/repo.git`) remotes.
    static func repositoryName(fromRemoteURL url: String) -> String? {
        var trimmed = url
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        let lastComponent = trimmed
            .split(whereSeparator: { $0 == "/" || $0 == ":" })
            .last
            .map(String.init)
        return (lastComponent?.isEmpty == false) ? lastComponent : nil
    }
}
