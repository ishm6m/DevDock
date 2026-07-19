import XCTest
@testable import DevDock

final class DatabaseServiceTests: XCTestCase {

    private func service(_ kind: DatabaseService.Kind, port: Int? = nil) -> DatabaseService {
        DatabaseService(kind: kind, port: port ?? kind.defaultPort, pid: 4242)
    }

    func testConnectionStringUsesServiceSchemeAndPort() {
        XCTAssertEqual(service(.postgres).connectionString, "postgresql://localhost:5432")
        XCTAssertEqual(service(.redis).connectionString, "redis://localhost:6379")
        XCTAssertEqual(service(.mongodb).connectionString, "mongodb://localhost:27017")
        XCTAssertEqual(service(.mysql).connectionString, "mysql://localhost:3306")
    }

    func testConnectionStringReflectsNonDefaultPort() {
        XCTAssertEqual(service(.postgres, port: 5555).connectionString, "postgresql://localhost:5555")
    }

    /// Supabase local ships fixed default credentials, so those are safe to embed;
    /// no other service fabricates a username or password.
    func testSupabaseUsesDocumentedLocalCredentials() {
        XCTAssertEqual(service(.supabase).connectionString,
                       "postgresql://postgres:postgres@localhost:54322/postgres")
    }

    func testOnlySupabaseEmbedsCredentials() {
        for kind in DatabaseService.Kind.allCases where kind != .supabase {
            XCTAssertFalse(service(kind).connectionString.contains("@"),
                           "\(kind) should not fabricate credentials")
        }
    }
}
