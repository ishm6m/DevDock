import XCTest
@testable import DevDock

final class ServerAttentionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let eightHours: TimeInterval = 8 * 3600

    // MARK: - Forgotten (uptime)

    func testForgottenWhenUptimeMeetsThreshold() {
        let (attention, _) = ServerAttention.evaluate(
            launchDate: now.addingTimeInterval(-eightHours),
            cpuPercent: 1,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: nil
        )
        XCTAssertTrue(attention.isForgotten)
        XCTAssertFalse(attention.isHighCPU)
        XCTAssertTrue(attention.needsAttention)
    }

    func testNotForgottenBelowThreshold() {
        let (attention, _) = ServerAttention.evaluate(
            launchDate: now.addingTimeInterval(-(eightHours - 60)),
            cpuPercent: 1,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: nil
        )
        XCTAssertFalse(attention.isForgotten)
        XCTAssertFalse(attention.needsAttention)
    }

    // MARK: - High CPU (sustained)

    func testHighCPUNotFlaggedOnFirstCrossing() {
        // First time over the threshold: start the clock, don't flag yet.
        let (attention, since) = ServerAttention.evaluate(
            launchDate: now,
            cpuPercent: 95,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: nil
        )
        XCTAssertFalse(attention.isHighCPU)
        XCTAssertEqual(since, now, "should record when high CPU began")
    }

    func testHighCPUFlaggedOncesSustained() {
        let began = now.addingTimeInterval(-ServerAttention.highCPUSustainedSeconds)
        let (attention, since) = ServerAttention.evaluate(
            launchDate: now,
            cpuPercent: 95,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: began
        )
        XCTAssertTrue(attention.isHighCPU)
        XCTAssertEqual(since, began, "the start marker is carried forward unchanged")
    }

    func testHighCPUResetsWhenCPUDrops() {
        let began = now.addingTimeInterval(-600)
        let (attention, since) = ServerAttention.evaluate(
            launchDate: now,
            cpuPercent: 12,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: began
        )
        XCTAssertFalse(attention.isHighCPU)
        XCTAssertNil(since, "dropping below the threshold clears the marker")
    }

    func testOldButBusyServerIsHighCPUNotForgotten() {
        // Up for 8h but pinned at high CPU: it's working, not forgotten — so "High CPU"
        // wins and "Idle" stays off, keeping the idle label honest.
        let began = now.addingTimeInterval(-ServerAttention.highCPUSustainedSeconds)
        let (attention, _) = ServerAttention.evaluate(
            launchDate: now.addingTimeInterval(-eightHours),
            cpuPercent: 99,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: began
        )
        XCTAssertFalse(attention.isForgotten)
        XCTAssertTrue(attention.isHighCPU)
    }

    func testOldButModeratelyActiveServerIsNotFlagged() {
        // Old but doing real work at 40% CPU: not idle, not high — no false-positive tag.
        let (attention, _) = ServerAttention.evaluate(
            launchDate: now.addingTimeInterval(-eightHours),
            cpuPercent: 40,
            forgottenAfter: eightHours,
            now: now,
            highCPUSince: nil
        )
        XCTAssertFalse(attention.needsAttention)
    }
}
