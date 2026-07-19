import Foundation

/// Recognizes locally-running databases directly from the port scan, using a mix
/// of well-known default ports and process-name matching. This is essentially free
/// because it reuses the data `PortScanner` already produced.
final class DatabaseDetector: @unchecked Sendable {

    func detect(from records: [PortScanRecord]) -> [DatabaseService] {
        var results: [DatabaseService] = []
        var seen: Set<String> = []
        for record in records {
            guard let kind = Self.classify(command: record.command, port: record.port) else { continue }
            let service = DatabaseService(kind: kind, port: record.port, pid: record.pid)
            if seen.insert(service.id).inserted {
                results.append(service)
            }
        }
        return results.sorted { $0.kind.displayName < $1.kind.displayName }
    }

    /// Classifies a listening socket as a database, or returns `nil`. Process name
    /// wins over port so a non-standard port is still recognized correctly.
    static func classify(command: String, port: Int) -> DatabaseService.Kind? {
        let name = command.lowercased()

        if name.contains("redis") { return .redis }
        if name.contains("mongod") { return .mongodb }
        if name.contains("mysqld") || name.contains("mariadb") { return .mysql }
        if name.contains("postgres") || name.contains("postmaster") {
            return port == DatabaseService.Kind.supabase.defaultPort ? .supabase : .postgres
        }

        switch port {
        case DatabaseService.Kind.supabase.defaultPort: return .supabase
        case DatabaseService.Kind.postgres.defaultPort: return .postgres
        case DatabaseService.Kind.redis.defaultPort: return .redis
        case DatabaseService.Kind.mongodb.defaultPort: return .mongodb
        case DatabaseService.Kind.mysql.defaultPort: return .mysql
        default: return nil
        }
    }
}
