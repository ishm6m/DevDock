import XCTest
@testable import DevDock

final class AutoStopTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let twoHours: TimeInterval = 2 * 3600

    // Comfortably idle / comfortably busy relative to the idle threshold.
    private let idleCPU = ServerAttention.idleCPUPercent - 1
    private let busyCPU = ServerAttention.idleCPUPercent + 10

    // MARK: - Qualification

    func testNotACandidateBelowThreshold() {
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours - 60,
            cpuPercent: idleCPU,
            thresholdSeconds: twoHours,
            candidateSince: nil,
            now: now
        )
        XCTAssertEqual(action, .none)
        XCTAssertNil(marker)
    }

    func testOldButBusyIsNeverACandidate() {
        // Past the threshold but actively working — must not be reaped.
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours * 3,
            cpuPercent: busyCPU,
            thresholdSeconds: twoHours,
            candidateSince: nil,
            now: now
        )
        XCTAssertEqual(action, .none)
        XCTAssertNil(marker)
    }

    // MARK: - Warn → grace → stop

    func testNewlyIdleAndOldWarnsAndOpensGraceWindow() {
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours,
            cpuPercent: idleCPU,
            thresholdSeconds: twoHours,
            candidateSince: nil,
            now: now
        )
        XCTAssertEqual(action, .warn)
        XCTAssertEqual(marker, now, "the grace window starts now")
    }

    func testStillIdleWithinGraceDoesNotStop() {
        let started = now.addingTimeInterval(-(AutoStop.graceInterval - 30))
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours,
            cpuPercent: idleCPU,
            thresholdSeconds: twoHours,
            candidateSince: started,
            now: now
        )
        XCTAssertEqual(action, .none)
        XCTAssertEqual(marker, started, "the marker is carried forward unchanged")
    }

    func testStillIdlePastGraceStops() {
        let started = now.addingTimeInterval(-AutoStop.graceInterval)
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours,
            cpuPercent: idleCPU,
            thresholdSeconds: twoHours,
            candidateSince: started,
            now: now
        )
        XCTAssertEqual(action, .stop)
        XCTAssertEqual(marker, started)
    }

    // MARK: - Cancellation

    func testCPUSpikeMidGraceCancelsThePendingStop() {
        // Was pending a stop, but CPU rose during the window: cancel and clear the marker.
        let started = now.addingTimeInterval(-(AutoStop.graceInterval - 10))
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours,
            cpuPercent: busyCPU,
            thresholdSeconds: twoHours,
            candidateSince: started,
            now: now
        )
        XCTAssertEqual(action, .none)
        XCTAssertNil(marker, "a busy lapse clears the grace window")
    }

    func testGoingIdleAgainAfterASpikeReWarnsBeforeStopping() {
        // After the spike cleared the marker, the next idle pass must warn again (never
        // jump straight to a stop without a fresh warning).
        let (action, marker) = AutoStop.evaluate(
            uptime: twoHours * 2,
            cpuPercent: idleCPU,
            thresholdSeconds: twoHours,
            candidateSince: nil,
            now: now
        )
        XCTAssertEqual(action, .warn)
        XCTAssertEqual(marker, now)
    }
}
