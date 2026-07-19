import Foundation

/// The inputs used to classify a process's framework. Bundling them into a value
/// type lets the classifier be a pure function that unit tests can drive directly.
struct FrameworkSignals {
    var arguments: [String]
    var executableBasename: String?
    /// Union of `dependencies` + `devDependencies` keys from package.json.
    var packageDependencies: Set<String>
    /// Lowercased contents of Python manifests (pyproject.toml / requirements.txt).
    var pythonManifest: String
    var projectMarkers: Set<ProjectInfo.Marker>
    var port: Int

    init(
        arguments: [String],
        executableBasename: String? = nil,
        packageDependencies: Set<String> = [],
        pythonManifest: String = "",
        projectMarkers: Set<ProjectInfo.Marker> = [],
        port: Int = 0
    ) {
        self.arguments = arguments
        self.executableBasename = executableBasename
        self.packageDependencies = packageDependencies
        self.pythonManifest = pythonManifest
        self.projectMarkers = projectMarkers
        self.port = port
    }
}

/// Pure framework classification. Ordered from the strongest, most specific
/// signals (an explicit CLI like `next dev`) down to weaker fallbacks (a runtime
/// binary, then a bare project marker), so specific frameworks always win.
enum FrameworkClassifier {

    static func classify(_ signals: FrameworkSignals) -> Framework {
        let tokens = signals.arguments.map { ($0 as NSString).lastPathComponent.lowercased() }
        func has(_ token: String) -> Bool { tokens.contains(token) }
        func hasAny(_ candidates: [String]) -> Bool { candidates.contains(where: has) }
        func contains(_ fragment: String) -> Bool { tokens.contains { $0.contains(fragment) } }

        // 1. Explicit CLI signals (strongest).
        if has("next") { return .nextjs }
        if has("vite") { return .vite }
        if has("astro") { return .astro }
        if hasAny(["nuxt", "nuxi"]) { return .nuxt }
        if hasAny(["remix", "remix-serve"]) { return .remix }
        if has("nest") { return .nestjs }
        if has("ng") { return .angular }
        if has("expo") { return .expo }
        if has("metro") { return .metro }
        if contains("react-native") && has("start") { return .metro }
        if has("uvicorn") { return .fastapi }
        if contains("manage.py") { return .django }
        if has("flask") { return .flask }
        if hasAny(["rails", "puma"]) { return .rails }
        if contains("artisan") { return .laravel }
        if has("php") && signals.arguments.contains("-S") { return .php }

        // 2. package.json dependency signals.
        let deps = signals.packageDependencies
        if deps.contains("next") { return .nextjs }
        if deps.contains("nuxt") { return .nuxt }
        if deps.contains("astro") { return .astro }
        if deps.contains("vite") { return .vite }
        if deps.contains("@angular/core") { return .angular }
        if deps.contains(where: { $0.hasPrefix("@remix-run") }) { return .remix }
        if deps.contains("@nestjs/core") { return .nestjs }
        if deps.contains("expo") { return .expo }
        if deps.contains("react-native") { return .metro }
        if deps.contains("express") { return .express }
        if deps.contains("vue") { return .vue }
        if deps.contains("react") { return .react }

        // 3. Python manifest signals.
        let manifest = signals.pythonManifest
        if !manifest.isEmpty {
            if manifest.contains("django") { return .django }
            if manifest.contains("fastapi") { return .fastapi }
            if manifest.contains("flask") { return .flask }
        }

        // 4. Runtime / executable fallback.
        if let exe = signals.executableBasename?.lowercased() {
            if exe == "bun" || has("bun") { return .bun }
            if exe == "deno" || has("deno") { return .deno }
            if exe == "go" { return .go }
            if exe == "php" { return .php }
            if exe.hasPrefix("node") { return .node }
        }

        // 5. Bare project-marker fallback.
        if signals.projectMarkers.contains(.goMod) { return .go }
        if signals.projectMarkers.contains(.cargoToml) { return .rust }
        if signals.projectMarkers.contains(.packageJSON) { return .node }

        return .unknown
    }
}

/// Loads on-disk manifests for a project and runs the pure classifier.
final class FrameworkDetector: @unchecked Sendable {

    func detect(arguments: [String], executablePath: String?, project: ProjectInfo?, port: Int) -> Framework {
        var dependencies: Set<String> = []
        var pythonManifest = ""
        var markers: Set<ProjectInfo.Marker> = []

        if let root = project?.rootPath {
            dependencies = Self.packageDependencies(atRoot: root)
            pythonManifest = Self.pythonManifest(atRoot: root)
        }
        if let marker = project?.marker {
            markers.insert(marker)
        }

        let signals = FrameworkSignals(
            arguments: arguments,
            executableBasename: executablePath.map { ($0 as NSString).lastPathComponent },
            packageDependencies: dependencies,
            pythonManifest: pythonManifest,
            projectMarkers: markers,
            port: port
        )
        return FrameworkClassifier.classify(signals)
    }

    /// Reads dependency + devDependency names from a project's package.json.
    static func packageDependencies(atRoot root: String) -> Set<String> {
        let path = (root as NSString).appendingPathComponent("package.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var names: Set<String> = []
        for key in ["dependencies", "devDependencies"] {
            if let section = json[key] as? [String: Any] {
                names.formUnion(section.keys)
            }
        }
        return names
    }

    /// Concatenates and lowercases Python manifests for keyword matching.
    static func pythonManifest(atRoot root: String) -> String {
        var combined = ""
        for file in ["pyproject.toml", "requirements.txt"] {
            let path = (root as NSString).appendingPathComponent(file)
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8) {
                combined += text.lowercased() + "\n"
            }
        }
        return combined
    }
}
