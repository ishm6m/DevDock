import Foundation
import Combine

/// Backs the live log window for a single managed server.
@MainActor
final class LogViewModel: ObservableObject {

    @Published var searchText = ""
    @Published var autoScroll = true

    let title: String
    private let managedPID: Int32?
    private let logService: LogService
    private var cancellable: AnyCancellable?

    init(title: String, managedPID: Int32?, logService: LogService) {
        self.title = title
        self.managedPID = managedPID
        self.logService = logService
        cancellable = logService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Logs are only capturable for servers DevDock launched.
    var isAvailable: Bool { managedPID != nil }

    var lines: [LogService.LogLine] {
        guard let managedPID else { return [] }
        let all = logService.lines(forPID: managedPID)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}
