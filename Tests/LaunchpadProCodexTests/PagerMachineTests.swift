import XCTest
@testable import LaunchpadProCodex

final class PagerMachineTests: XCTestCase {
    private func machine(page: Int = 1, width: CGFloat = 1500, count: Int = 4) -> PagerMachine {
        var machine = PagerMachine()
        machine.configure(pageWidth: width, pageCount: count)
        machine.jump(to: page)
        return machine
    }

    private func settle(_ machine: inout PagerMachine, after time: TimeInterval) {
        for frame in 1...120 {
            machine.tick(targetTime: time + Double(frame) / 120)
            if !machine.needsFrames { break }
        }
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.needsFrames)
        XCTAssertEqual(machine.stripX, CGFloat(machine.targetPage) * machine.pageWidth)
        XCTAssertEqual(machine.restingPage, machine.targetPage)
        XCTAssertEqual(machine.velocity, 0)
    }

    func testConservesFiveHundredSignedDeltasIncludingBeganAndEnded() {
        var machine = machine()
        var random = PhysicsRandom(seed: 42)
        var sum: CGFloat = 0
        var positives = 0
        var negatives = 0
        for index in 0..<500 {
            let dx: CGFloat = index == 0 ? 4 : CGFloat(random.signedUnit() * 5)
            sum += dx
            if dx > 0 { positives += 1 } else { negatives += 1 }
            let phase: ScrollPhase = index == 0 ? .began : index == 499 ? .ended : .changed
            machine.scroll(dx: dx, dy: 0, phase: phase, time: Double(index) / 120)
            XCTAssertEqual(machine.gestureRawDX, sum, accuracy: 1e-6)
            XCTAssertEqual(machine.stripX, 1500 - sum, accuracy: 1e-6)
        }
        XCTAssertGreaterThan(positives, 0)
        XCTAssertGreaterThan(negatives, 0)
    }

    func testAxisLockCompensationAndVerticalRejection() {
        var horizontal = machine()
        horizontal.scroll(dx: 2, dy: 1, phase: .began, time: 0)
        XCTAssertEqual(horizontal.phase, .pendingAxis)
        XCTAssertEqual(horizontal.stripX, 1500)
        XCTAssertTrue(horizontal.needsFrames)
        horizontal.scroll(dx: 2, dy: 1, phase: .changed, time: 0.01)
        XCTAssertEqual(horizontal.phase, .tracking)
        XCTAssertEqual(horizontal.stripX, 1496)
        XCTAssertEqual(horizontal.gestureRawDX, 4)

        var vertical = machine()
        vertical.scroll(dx: 1, dy: 2, phase: .began, time: 0)
        vertical.scroll(dx: 1, dy: 2, phase: .changed, time: 0.01)
        XCTAssertEqual(vertical.phase, .ignoring)
        XCTAssertFalse(vertical.needsFrames)
        vertical.scroll(dx: 500, dy: 0, phase: .changed, time: 0.02)
        XCTAssertEqual(vertical.stripX, 1500)
        XCTAssertEqual(vertical.gestureRawDX, 0)
        vertical.scroll(dx: 0, dy: 0, phase: .ended, time: 0.03)
        XCTAssertEqual(vertical.phase, .idle)
    }

    func testEndedDeltaCanLockAxisAndIsIncludedInDecision() {
        var machine = machine()
        machine.scroll(dx: -2, dy: 0, phase: .began, time: 0)
        machine.scroll(dx: -198, dy: 0, phase: .ended, time: 1)
        XCTAssertEqual(machine.gestureRawDX, -200)
        XCTAssertEqual(machine.stripX, 1700)
        XCTAssertEqual(machine.targetPage, 2)
        settle(&machine, after: 1)
    }

    func testShortPendingGestureReturnsToStart() {
        var machine = machine()
        machine.scroll(dx: 1, dy: 0, phase: .began, time: 0)
        machine.scroll(dx: 1, dy: 0, phase: .ended, time: 0.02)
        XCTAssertEqual(machine.targetPage, 1)
        XCTAssertEqual(machine.stripX, 1500)
        settle(&machine, after: 0.02)
    }

    func testStoppedFlickDoesNotFlipAndReleaseInheritsVelocity() {
        var moving = machine()
        moving.scroll(dx: 0, dy: 0, phase: .began, time: 0)
        moving.scroll(dx: -10, dy: 0, phase: .changed, time: 0.01)
        var stopped = moving
        moving.scroll(dx: 0, dy: 0, phase: .ended, time: 0.01)
        XCTAssertEqual(moving.targetPage, 2)
        XCTAssertEqual(moving.velocity, 1000, accuracy: 1e-6)
        let releasePosition = moving.stripX
        moving.tick(targetTime: 0.01)
        XCTAssertEqual(moving.stripX, releasePosition, accuracy: 1e-6)
        XCTAssertEqual(moving.velocity, 1000, accuracy: 1e-6)
        stopped.scroll(dx: 0, dy: 0, phase: .ended, time: 0.07)
        XCTAssertEqual(stopped.targetPage, 1)
        XCTAssertEqual(stopped.velocity, 0)
    }

    func testConsecutiveQuickGesturesInheritTargetPage() {
        var machine = machine(page: 0)
        machine.scroll(dx: 0, dy: 0, phase: .began, time: 0)
        machine.scroll(dx: -400, dy: 0, phase: .ended, time: 0.1)
        XCTAssertEqual(machine.targetPage, 1)
        machine.tick(targetTime: 0.28)
        XCTAssertEqual(machine.phase, .snapping)
        XCTAssertEqual(machine.restingPage, 0)
        let displayed = machine.stripX
        machine.scroll(dx: 0, dy: 0, phase: .began, time: 0.28)
        XCTAssertEqual(machine.startPage, 1)
        XCTAssertEqual(machine.stripX, displayed, accuracy: 1e-6)
        machine.scroll(dx: -500, dy: 0, phase: .ended, time: 0.38)
        XCTAssertEqual(machine.targetPage, 2)
        settle(&machine, after: 0.38)
    }

    func testMayBeginFreezesAndCancelledOrEndedSnapsToNearestPage() {
        for input in [ScrollPhase.cancelled, .ended] {
            for elapsed in [0.04, 0.15] {
                var machine = machine(page: 0)
                machine.snap(to: 1, velocity: 0, time: 0)
                machine.tick(targetTime: elapsed)
                let displayed = machine.stripX
                machine.scroll(dx: 0, dy: 0, phase: .mayBegin, time: elapsed)
                XCTAssertEqual(machine.phase, .caught)
                XCTAssertTrue(machine.needsFrames)
                machine.tick(targetTime: elapsed + 0.1)
                XCTAssertEqual(machine.stripX, displayed)
                machine.scroll(dx: 0, dy: 0, phase: input, time: elapsed + 0.11)
                XCTAssertEqual(machine.targetPage, Int((displayed / 1500).rounded()))
                XCTAssertEqual(machine.velocity, 0)
                settle(&machine, after: elapsed + 0.11)
            }
        }
    }

    func testCaughtBeganKeepsTargetAndVerticalGestureSettlesNearest() {
        var caught = machine(page: 0)
        caught.snap(to: 2, velocity: 0, time: 0)
        caught.tick(targetTime: 0.1)
        let displayed = caught.stripX
        caught.scroll(dx: 0, dy: 0, phase: .mayBegin, time: 0.1)
        caught.scroll(dx: 0, dy: 0, phase: .began, time: 0.11)
        XCTAssertEqual(caught.startPage, 2)
        caught.scroll(dx: 0, dy: 10, phase: .changed, time: 0.12)
        XCTAssertEqual(caught.phase, .ignoring)
        caught.scroll(dx: 0, dy: 0, phase: .ended, time: 0.13)
        XCTAssertEqual(caught.targetPage, Int((displayed / 1500).rounded()))
        settle(&caught, after: 0.13)
    }

    func testCancelledPendingAndTrackingReturnToStart() {
        for dx: CGFloat in [-1, -700] {
            var machine = machine()
            machine.scroll(dx: dx, dy: 0, phase: .began, time: 0)
            machine.scroll(dx: -100, dy: 0, phase: .cancelled, time: 0.1)
            XCTAssertEqual(machine.targetPage, 1)
            XCTAssertEqual(machine.velocity, 0)
            settle(&machine, after: 0.1)
        }
    }

    func testLockIgnoresScrollAndAllowsProgrammaticPaging() {
        var machine = machine()
        machine.setLocked(true, time: 0)
        for input in [ScrollPhase.mayBegin, .began, .changed, .ended, .cancelled, .other] {
            machine.scroll(dx: -400, dy: 0, phase: input, time: 0.1)
        }
        XCTAssertEqual(machine.stripX, 1500)
        XCTAssertEqual(machine.phase, .idle)
        machine.snap(to: 2, velocity: 0, time: 0.2)
        settle(&machine, after: 0.2)
        machine.setLocked(false, time: 1)
        machine.scroll(dx: 0, dy: 0, phase: .began, time: 1)
        XCTAssertEqual(machine.phase, .pendingAxis)
    }

    func testLockDuringGestureReturnsToStartingPage() {
        for dx: CGFloat in [-1, -700] {
            var machine = machine()
            machine.scroll(dx: dx, dy: 0, phase: .began, time: 0)
            let displayed = machine.stripX
            machine.setLocked(true, time: 0.1)
            XCTAssertEqual(machine.stripX, displayed)
            XCTAssertEqual(machine.targetPage, 1)
            XCTAssertEqual(machine.velocity, 0)
            settle(&machine, after: 0.1)
        }
    }

    func testConfigureClampsIdleAndRetargetsSpringWithoutLosingVelocity() {
        var idle = machine(page: 3)
        idle.configure(pageWidth: 1200, pageCount: 2)
        XCTAssertEqual(idle.targetPage, 1)
        XCTAssertEqual(idle.restingPage, 1)
        XCTAssertEqual(idle.stripX, 1200)

        var snapping = machine(page: 0)
        snapping.snap(to: 3, velocity: 1000, time: 0)
        snapping.tick(targetTime: 0.1)
        let displayed = snapping.stripX
        let velocity = snapping.velocity
        snapping.configure(pageWidth: 1000, pageCount: 2)
        XCTAssertEqual(snapping.targetPage, 1)
        XCTAssertEqual(snapping.stripX, displayed)
        XCTAssertEqual(snapping.velocity, velocity)
        snapping.tick(targetTime: 0.1)
        XCTAssertEqual(snapping.stripX, displayed, accuracy: 1e-6)
        XCTAssertEqual(snapping.velocity, velocity, accuracy: 1e-6)
        settle(&snapping, after: 0.1)
    }

    func testConfigureDuringTrackingOnlyChangesBounds() {
        var machine = machine(page: 2)
        machine.scroll(dx: -200, dy: 0, phase: .began, time: 0)
        let displayed = machine.stripX
        machine.configure(pageWidth: 1500, pageCount: 2)
        XCTAssertEqual(machine.phase, .tracking)
        XCTAssertEqual(machine.stripX, displayed)
        XCTAssertEqual(machine.gestureRawDX, -200)
        machine.scroll(dx: 0, dy: 0, phase: .ended, time: 0.1)
        XCTAssertEqual(machine.targetPage, 1)
        settle(&machine, after: 0.1)
    }

    func testJumpClampsAndImmediatelyCancelsGestureOrSpring() {
        var machine = machine()
        machine.scroll(dx: -300, dy: 0, phase: .began, time: 0)
        machine.jump(to: 99)
        XCTAssertEqual(machine.targetPage, 3)
        XCTAssertEqual(machine.restingPage, 3)
        XCTAssertEqual(machine.stripX, 4500)
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.needsFrames)
        machine.snap(to: 1, velocity: 1000, time: 0.1)
        machine.jump(to: -1)
        machine.tick(targetTime: 0.5)
        XCTAssertEqual(machine.stripX, 0)
        XCTAssertEqual(machine.restingPage, 0)
        XCTAssertEqual(machine.velocity, 0)
    }

    func testRubberBandReleaseVelocityAndInterruptionAreContinuous() {
        for page in [0, 3] {
            var machine = machine(page: page)
            let sign: CGFloat = page == 0 ? 1 : -1
            machine.scroll(dx: 0, dy: 0, phase: .began, time: 0)
            for index in 1...10 {
                machine.scroll(dx: sign * 10, dy: 0, phase: .changed, time: Double(index) * 0.01)
            }
            let band = RubberBand(limit: 450)
            let displayed = CGFloat(page) * 1500 - sign * band.apply(100)
            XCTAssertEqual(machine.stripX, displayed, accuracy: 1e-6)
            machine.scroll(dx: 0, dy: 0, phase: .ended, time: 0.1)
            XCTAssertEqual(machine.targetPage, page)
            XCTAssertEqual(machine.stripX, displayed, accuracy: 1e-6)
            XCTAssertEqual(machine.velocity, -sign * 1000 * band.derivative(at: 100), accuracy: 1e-6)
            machine.scroll(dx: 0, dy: 0, phase: .mayBegin, time: 0.1)
            machine.scroll(dx: 0, dy: 0, phase: .began, time: 0.11)
            machine.scroll(dx: sign * 10, dy: 0, phase: .changed, time: 0.12)
            XCTAssertEqual(machine.stripX, CGFloat(page) * 1500 - sign * band.apply(110), accuracy: 1e-6)
            machine.scroll(dx: 0, dy: 0, phase: .cancelled, time: 0.13)
            settle(&machine, after: 0.13)
        }
    }

    func testSnapNilInheritsCurrentDisplayedVelocity() {
        var machine = machine(page: 0)
        machine.snap(to: 1, velocity: 1000, time: 0)
        machine.tick(targetTime: 0.1)
        let displayed = machine.stripX
        let velocity = machine.velocity
        machine.snap(to: 2, time: 0.1)
        machine.tick(targetTime: 0.1)
        XCTAssertEqual(machine.stripX, displayed, accuracy: 1e-6)
        XCTAssertEqual(machine.velocity, velocity, accuracy: 1e-6)
        machine.snap(to: 1, velocity: 0, time: 0.1)
        XCTAssertEqual(machine.velocity, 0)
    }

    func testDirectTicksDoNotMoveAndPredictionDoesNotAccumulateIntoRaw() {
        var direct = machine()
        direct.scroll(dx: 0, dy: 0, phase: .began, time: 0)
        direct.scroll(dx: -10, dy: 0, phase: .changed, time: 0.01)
        var predicted = direct
        predicted.predictEnabled = true
        direct.tick(targetTime: 0.02)
        XCTAssertEqual(direct.stripX, 1510)
        predicted.tick(targetTime: 0.02, frameDuration: 0.008)
        XCTAssertEqual(predicted.stripX, 1518, accuracy: 1e-6)
        predicted.tick(targetTime: 0.025, frameDuration: 0.008)
        XCTAssertEqual(predicted.stripX, 1518, accuracy: 1e-6)
        XCTAssertEqual(predicted.gestureRawDX, -10)
        predicted.tick(targetTime: 0.041)
        XCTAssertEqual(predicted.stripX, 1510)
        direct.scroll(dx: -10, dy: 0, phase: .changed, time: 0.05)
        predicted.scroll(dx: -10, dy: 0, phase: .changed, time: 0.05)
        XCTAssertEqual(predicted.stripX, direct.stripX)
        XCTAssertEqual(predicted.gestureRawDX, direct.gestureRawDX)
    }

    func testEmptyGeometryAndStrayEventsRemainIdle() {
        var machine = machine()
        machine.configure(pageWidth: 0, pageCount: 0)
        XCTAssertEqual(machine.targetPage, 0)
        XCTAssertEqual(machine.stripX, 0)
        for input in [ScrollPhase.changed, .ended, .cancelled, .other, .mayBegin] {
            machine.scroll(dx: 100, dy: 0, phase: input, time: 0.1)
        }
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.needsFrames)
    }
}
