import Foundation

/// A locally-running database or backing service detected from the port scan.
struct DatabaseService: Identifiable, Hashable {

    enum Kind: String, Codable, CaseIterable {
        case postgres
        case redis
        case mongodb
        case mysql
        case supabase

        var displayName: String {
            switch self {
            case .postgres: return "PostgreSQL"
            case .redis: return "Redis"
            case .mongodb: return "MongoDB"
            case .mysql: return "MySQL"
            case .supabase: return "Supabase (local)"
            }
        }

        var symbol: String {
            switch self {
            case .redis: return "bolt.horizontal.circle"
            case .supabase: return "leaf"
            default: return "cylinder.split.1x2"
            }
        }

        var accentColorHex: String {
            switch self {
            case .postgres: return "#336791"
            case .redis: return "#DC382D"
            case .mongodb: return "#47A248"
            case .mysql: return "#4479A1"
            case .supabase: return "#3ECF8E"
            }
        }

        /// The conventional default port each service listens on.
        var defaultPort: Int {
            switch self {
            case .postgres: return 5432
            case .redis: return 6379
            case .mongodb: return 27017
            case .mysql: return 3306
            case .supabase: return 54322
            }
        }
    }

    let kind: Kind
    let port: Int
    let pid: Int32

    var id: String { "\(kind.rawValue)-\(port)" }
    var displayName: String { kind.displayName }

    /// A best-effort connection URI using the conventional local defaults. Credentials
    /// are only included where they are a well-known fixed default (Supabase local,
    /// which ships `postgres:postgres`); every other service is just `scheme://host:port`
    /// so nothing is fabricated.
    var connectionString: String {
        switch kind {
        case .postgres: return "postgresql://localhost:\(port)"
        case .redis:    return "redis://localhost:\(port)"
        case .mongodb:  return "mongodb://localhost:\(port)"
        case .mysql:    return "mysql://localhost:\(port)"
        case .supabase: return "postgresql://postgres:postgres@localhost:\(port)/postgres"
        }
    }
}
