import Foundation
import Combine
import AppKit

/// The view model backing the menu bar panel.
///
/// It bridges the several underlying `ObservableObject`s (discovery, favorites,
/// preferences) into one observable surface, exposes search-filtered and
/// favorite-partitioned collections, and routes user actions to `ServerCommands`.
@MainActor
final class MenuBarViewModel: ObservableObject {

    @Published var searchText = ""
    @Published var showKillAllConfirmation = false
    @Published var pendingKill: DevServer?
    @Published private(set) var recentlyCopiedID: String?

    /// Server IDs with a kill/restart currently in flight. Used to disable their
    /// action buttons and to reject duplicate taps (which is how restart used to be
    /// able to spawn duplicate processes).
    @Published private(set) var inFlightServerIDs: Set<String> = []

    /// A transient status message shown after an action completes.
    @Published private(set) var feedback: ActionFeedback?

    let environment: AppEnvironment
    private var cancellables: Set<AnyCancellable> = []
    private var feedbackDismissTask: Task<Void, Never>?

    /// A short-lived toast describing the result of a user action.
    struct ActionFeedback: Identifiable, Equatable {
        enum Style { case success, warning, error }
        let id = UUID()
        let message: String
        let style: Style
        let symbol: String
    }

    init(environment: AppEnvironment) {
        self.environment = environment

        // Re-publish nested observable objects so a single @ObservedObject drives the UI.
        for publisher in [
            environment.coordinator.objectWillChange,
            environment.favoritesStore.objectWillChange,
            environment.preferencesStore.objectWillChange,
        ] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: - Derived state

    var preferences: Preferences { environment.preferencesStore.preferences }
    var activeServerCount: Int { environment.coordinator.servers.count }

    /// Servers eligible for "Kill All". Pinned favorites are deliberately excluded so a
    /// bulk reap never takes down a project you care about — kill those individually.
    /// Uses the unfiltered set so search text never changes what a bulk kill targets.
    var killableServers: [DevServer] {
        environment.coordinator.servers.filter { !environment.favoritesStore.isFavorite($0) }
    }

    var killableServerCount: Int { killableServers.count }

    /// Servers currently flagged as forgotten or burning CPU.
    var attentionCount: Int {
        environment.coordinator.servers.filter { $0.attention.needsAttention }.count
    }

    private var filteredServers: [DevServer] {
        let all = environment.coordinator.servers
        guard !trimmedSearch.isEmpty else { return all }
        return all.filter { matches($0) }
    }

    /// Pinned servers, kept in the engine's ordering.
    var favoriteServers: [DevServer] {
        filteredServers.filter { environment.favoritesStore.isFavorite($0) }
    }

    /// Everything else.
    var otherServers: [DevServer] {
        filteredServers.filter { !environment.favoritesStore.isFavorite($0) }
    }

    var databases: [DatabaseService] {
        let all = environment.coordinator.databases
        guard !trimmedSearch.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmedSearch) || String($0.port).contains(trimmedSearch)
        }
    }

    var containers: [DockerContainer] {
        let all = environment.coordinator.containers
        guard !trimmedSearch.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
                || $0.image.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var tunnels: [Tunnel] {
        let all = environment.coordinator.tunnels
        guard !trimmedSearch.isEmpty else { return all }
        return all.filter {
            $0.kind.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || ($0.publicURL ?? "").localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var hasAnything: Bool {
        !environment.coordinator.servers.isEmpty
            || !environment.coordinator.databases.isEmpty
            || !environment.coordinator.containers.isEmpty
            || !environment.coordinator.tunnels.isEmpty
    }

    var conflictPortsSummary: [Int] {
        environment.coordinator.conflictPorts.sorted()
    }

    func isFavorite(_ server: DevServer) -> Bool {
        environment.favoritesStore.isFavorite(server)
    }

    // MARK: - Actions

    /// True while a kill/restart is in flight for this server.
    func isBusy(_ server: DevServer) -> Bool { inFlightServerIDs.contains(server.id) }

    func open(_ server: DevServer) { environment.commands.open(server) }

    func reveal(_ server: DevServer) {
        if !environment.commands.reveal(server) {
            showFeedback("Project folder not found", style: .warning, symbol: "folder.badge.questionmark")
        }
    }

    func toggleFavorite(_ server: DevServer) { environment.favoritesStore.toggle(server) }

    func copyURL(_ server: DevServer) {
        environment.commands.copyURL(server)
        recentlyCopiedID = server.id
        let id = server.id
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if self.recentlyCopiedID == id { self.recentlyCopiedID = nil }
        }
    }

    func copyConnectionString(_ database: DatabaseService) {
        environment.commands.copyConnectionString(database)
        showFeedback("Copied \(database.displayName) connection string",
                     style: .success, symbol: "doc.on.clipboard.fill")
    }

    func requestKill(_ server: DevServer) {
        if preferences.confirmBeforeKill {
            pendingKill = server
        } else {
            performKill(server)
        }
    }

    func confirmPendingKill() {
        if let server = pendingKill { performKill(server) }
        pendingKill = nil
    }

    private func performKill(_ server: DevServer) {
        runExclusive(server) { [weak self] in
            guard let self else { return }
            let outcome = await self.environment.commands.kill(server)
            await self.environment.coordinator.refresh()
            self.showFeedback(
                outcome.userMessage,
                style: outcome.didStopProcess ? .success : .error,
                symbol: outcome.didStopProcess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
        }
    }

    func restart(_ server: DevServer) {
        runExclusive(server) { [weak self] in
            guard let self else { return }
            let succeeded = await self.environment.commands.restart(server)
            await self.environment.coordinator.refresh()
            if succeeded {
                self.showFeedback("Restarted \(server.title)", style: .success, symbol: "arrow.clockwise.circle.fill")
            } else {
                self.showFeedback("Couldn't restart \(server.title)", style: .error, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Runs an exclusive kill/restart for a server, rejecting concurrent taps so a
    /// double click can never spawn a duplicate process or double-signal a PID.
    private func runExclusive(_ server: DevServer, _ work: @escaping () async -> Void) {
        guard !inFlightServerIDs.contains(server.id) else { return }
        inFlightServerIDs.insert(server.id)
        Task {
            await work()
            inFlightServerIDs.remove(server.id)
        }
    }

    func requestKillAll() {
        guard !killableServers.isEmpty else { return }
        showKillAllConfirmation = true
    }

    func confirmKillAll() {
        // Dismiss the overlay up front (async kill runs after) — otherwise the
        // confirmation stays on screen because the request is derived from this flag.
        showKillAllConfirmation = false
        let servers = killableServers
        guard !servers.isEmpty else { return }
        Task {
            let outcomes = await environment.commands.killAll(servers)
            await environment.coordinator.refresh()
            let stopped = outcomes.filter(\.didStopProcess).count
            showFeedback(
                "Stopped \(stopped) of \(servers.count) server\(servers.count == 1 ? "" : "s")",
                style: stopped == servers.count ? .success : .warning,
                symbol: "xmark.octagon.fill"
            )
        }
    }

    func refreshNow() {
        Task { await environment.coordinator.refresh() }
    }

    // MARK: - Feedback

    func showFeedback(_ message: String, style: ActionFeedback.Style, symbol: String) {
        let item = ActionFeedback(message: message, style: style, symbol: symbol)
        feedback = item
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.feedback?.id == item.id else { return }
            self.feedback = nil
        }
    }

    // MARK: - Docker / tunnel actions

    /// Container IDs with a stop/restart currently in flight.
    @Published private(set) var inFlightContainerIDs: Set<String> = []

    func isBusy(_ container: DockerContainer) -> Bool { inFlightContainerIDs.contains(container.id) }

    func openContainer(_ container: DockerContainer) {
        if let url = container.primaryURL { environment.commands.open(url: url) }
    }

    func stopContainer(_ container: DockerContainer) {
        runExclusive(container) { [weak self] in
            guard let self else { return }
            let ok = await self.environment.dockerService.stop(id: container.id)
            await self.environment.coordinator.refresh()
            self.showFeedback(
                ok ? "Stopped \(container.name)" : "Couldn't stop \(container.name)",
                style: ok ? .success : .error,
                symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
        }
    }

    func restartContainer(_ container: DockerContainer) {
        runExclusive(container) { [weak self] in
            guard let self else { return }
            let ok = await self.environment.dockerService.restart(id: container.id)
            await self.environment.coordinator.refresh()
            self.showFeedback(
                ok ? "Restarted \(container.name)" : "Couldn't restart \(container.name)",
                style: ok ? .success : .error,
                symbol: ok ? "arrow.clockwise.circle.fill" : "exclamationmark.triangle.fill"
            )
        }
    }

    private func runExclusive(_ container: DockerContainer, _ work: @escaping () async -> Void) {
        guard !inFlightContainerIDs.contains(container.id) else { return }
        inFlightContainerIDs.insert(container.id)
        Task {
            await work()
            inFlightContainerIDs.remove(container.id)
        }
    }

    func openTunnel(_ tunnel: Tunnel) {
        if let url = tunnel.publicWebURL { environment.commands.open(url: url) }
    }

    func quit() { NSApp.terminate(nil) }

    // MARK: - Search matching

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ server: DevServer) -> Bool {
        let query = trimmedSearch.lowercased()
        if server.title.lowercased().contains(query) { return true }
        if server.framework.displayName.lowercased().contains(query) { return true }
        if String(server.port.number).contains(query) { return true }
        if let branch = server.git?.branch?.lowercased(), branch.contains(query) { return true }
        if let repo = server.git?.repositoryName?.lowercased(), repo.contains(query) { return true }
        if server.command.lowercased().contains(query) { return true }
        return false
    }
}
