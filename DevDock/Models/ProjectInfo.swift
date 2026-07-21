import Foundation

/// The resolved project root for a running server, plus how it was identified.
struct ProjectInfo: Hashable, Codable {

    /// The marker file/directory that identified the project root, in priority order.
    enum Marker: String, Codable, CaseIterable {
        case packageJSON = "package.json"
        case cargoToml = "Cargo.toml"
        case goMod = "go.mod"
        case pyprojectToml = "pyproject.toml"
        case composerJSON = "composer.json"
        case gemfile = "Gemfile"
        case git = ".git"
    }

    let rootPath: String
    let marker: Marker

    /// The project's display name, taken from the root directory name.
    var name: String {
        (rootPath as NSString).lastPathComponent
    }

    var abbreviatedPath: String { Formatters.abbreviatePath(rootPath) }
}
