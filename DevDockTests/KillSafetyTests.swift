import XCTest
@testable import DevDock

/// Guards the single most safety-critical path in the app: DevDock must never
/// signal an invalid PID or its own process. `kill(2)` treats non-positive PIDs as
/// process-group / broadcast targets, so a stale `pid == 0` would otherwise take the
/// whole app down.
final class KillSafetyTests: XCTestCase {

    // MARK: - Proc.isSafeToSignal

    func testZeroIsNeverSafe() {
        // kill(0, sig) signals the entire process group — including DevDock.
        XCTAssertFalse(Proc.isSafeToSignal(0))
    }

    func testNegativeIsNeverSafe() {
        // kill(-1, sig) broadcasts; kill(-g, sig) hits a whole group.
        XCTAssertFalse(Proc.isSafeToSignal(-1))
        XCTAssertFalse(Proc.isSafeToSignal(-1234))
    }

    func testLaunchdIsNeverSafe() {
        XCTAssertFalse(Proc.isSafeToSignal(1))
    }

    func testOwnProcessIsNeverSafe() {
        XCTAssertFalse(Proc.isSafeToSignal(Proc.ownPID))
        XCTAssertFalse(Proc.isSafeToSignal(getpid()))
    }

    func testOtherRealPIDIsSafe() {
        // A plausible other PID is a legitimate target.
        let other = Proc.ownPID == 99 ? Int32(100) : Int32(99)
        XCTAssertTrue(Proc.isSafeToSignal(other))
    }

    // MARK: - Proc.isAlive

    func testIsAliveRejectsNonPositivePIDs() {
        // Must not use kill(0, 0) as a liveness probe (it "succeeds" for the group).
        XCTAssertFalse(Proc.isAlive(0))
        XCTAssertFalse(Proc.isAlive(-1))
    }

    func testIsAliveTrueForOwnProcess() {
        XCTAssertTrue(Proc.isAlive(Proc.ownPID))
    }

    // MARK: - KillStrategy refuses unsafe targets without signalling

    func testTerminateRefusesZero() async {
        let outcome = await KillStrategy.terminate(pid: 0)
        XCTAssertEqual(outcome, .refusedUnsafe)
        XCTAssertFalse(outcome.didStopProcess)
    }

    func testTerminateRefusesOwnPID() async {
        let outcome = await KillStrategy.terminate(pid: Proc.ownPID)
        XCTAssertEqual(outcome, .refusedUnsafe)
    }

    func testTerminateRefusesNegative() async {
        let outcome = await KillStrategy.terminate(pid: -1)
        XCTAssertEqual(outcome, .refusedUnsafe)
    }

    // MARK: - KillOutcome semantics

    func testDidStopProcessClassification() {
        XCTAssertTrue(KillOutcome.terminated.didStopProcess)
        XCTAssertTrue(KillOutcome.killed.didStopProcess)
        XCTAssertTrue(KillOutcome.alreadyGone.didStopProcess)
        XCTAssertFalse(KillOutcome.notPermitted.didStopProcess)
        XCTAssertFalse(KillOutcome.refusedUnsafe.didStopProcess)
        XCTAssertFalse(KillOutcome.failed.didStopProcess)
    }
}
