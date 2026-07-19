import Foundation

/// Lightweight git metadata read directly from the `.git` directory (no `git` CLI).
struct GitInfo: Hashable, Codable {
    let repositoryName: String?
    let branch: String?

    var hasBranch: Bool { !(branch ?? "").isEmpty }
}
