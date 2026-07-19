import Foundation
import Combine

/// Persists the set of pinned favorites.
///
/// A favorite is keyed by the project root path when known (so it survives the
/// server restarting with a new PID/port), falling back to the server title.
/// Pinned servers are floated to the top of the list by the view model.
@MainActor
final class FavoritesStore: ObservableObject {

    @Published private(set) var favoriteKeys: Set<String> = []

    private let defaults: UserDefaults
    private let storageKey = "com.devdock.favorites.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.stringArray(forKey: storageKey) {
            favoriteKeys = Set(stored)
        }
    }

    static func key(for server: DevServer) -> String {
        server.project?.rootPath ?? server.title
    }

    func isFavorite(_ server: DevServer) -> Bool {
        favoriteKeys.contains(Self.key(for: server))
    }

    func toggle(_ server: DevServer) {
        let key = Self.key(for: server)
        if favoriteKeys.contains(key) {
            favoriteKeys.remove(key)
        } else {
            favoriteKeys.insert(key)
        }
        persist()
    }

    private func persist() {
        defaults.set(Array(favoriteKeys), forKey: storageKey)
    }
}
