import Foundation

/// Resolves a project root by walking upward from a process's working directory,
/// looking for well-known project markers.
///
/// The closest ancestor that contains any marker wins; within a directory, markers
/// are checked in the priority order declared on `ProjectInfo.Marker` (so a
/// package.json next to a .git resolves as a package.json project).
final class ProjectLocator: @unchecked Sendable {

    private let fileManager: FileManager
    private let maxDepth: Int

    init(fileManager: FileManager = .default, maxDepth: Int = 40) {
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    func locate(fromWorkingDirectory directory: String?) -> ProjectInfo? {
        guard let start = directory, !start.isEmpty else { return nil }

        var current = URL(fileURLWithPath: start).standardizedFileURL.path
        var depth = 0

        while depth < maxDepth {
            for marker in ProjectInfo.Marker.allCases {
                let candidate = (current as NSString).appendingPathComponent(marker.rawValue)
                if fileManager.fileExists(atPath: candidate) {
                    return ProjectInfo(rootPath: current, marker: marker)
                }
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty || parent == "/" { break }
            current = parent
            depth += 1
        }
        return nil
    }
}
