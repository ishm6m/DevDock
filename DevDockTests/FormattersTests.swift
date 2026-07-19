import XCTest
@testable import DevDock

final class FormattersTests: XCTestCase {

    func testMemoryZero() {
        XCTAssertEqual(Formatters.memory(bytes: 0), "—")
    }

    func testMemoryMegabytes() {
        XCTAssertEqual(Formatters.memory(bytes: 310 * 1024 * 1024), "310 MB")
    }

    func testMemoryGigabytesUsesOneDecimal() {
        XCTAssertEqual(Formatters.memory(bytes: 1_500_000_000), "1.4 GB")
    }

    func testCPUPercent() {
        XCTAssertEqual(Formatters.cpu(percent: 18), "18%")
        XCTAssertEqual(Formatters.cpu(percent: 0), "0%")
        XCTAssertEqual(Formatters.cpu(percent: -5), "0%")
    }

    func testDurationHoursAndMinutes() {
        XCTAssertEqual(Formatters.duration(seconds: 6_120), "1h 42m")
    }

    func testDurationMinutesAndSeconds() {
        XCTAssertEqual(Formatters.duration(seconds: 192), "3m 12s")
    }

    func testDurationSecondsOnly() {
        XCTAssertEqual(Formatters.duration(seconds: 8), "8s")
    }

    func testDurationDaysAndHours() {
        XCTAssertEqual(Formatters.duration(seconds: 90_000), "1d 1h")
    }
}
