import XCTest
@testable import LaunchpadProCodex

final class FrameMeterTests: XCTestCase {
    func testSyntheticTicksAndPercentiles() {
        var stats = FrameStats()
        for time in [0.0, 0.01, 0.02, 0.04, 0.05] {
            stats.tick(timestamp: time, target: time + 0.01, now: time + 0.001, position: time * 100, tracking: true)
        }
        XCTAssertEqual(stats.ticks, 5)
        XCTAssertEqual(stats.hz, 80, accuracy: 1e-9)
        XCTAssertEqual(FrameStats.percentile(stats.intervals, 0.5), 0.01, accuracy: 1e-9)
        XCTAssertEqual(FrameStats.percentile(stats.intervals, 0.95), 0.0185, accuracy: 1e-9)
        XCTAssertEqual(FrameStats.percentile(stats.intervals, 1), 0.02, accuracy: 1e-9)
        XCTAssertEqual(stats.hitches, 1)
    }

    func testEventLatencyUsesFirstFollowingTick() {
        var stats = FrameStats()
        stats.event(time: 0.002, raw: -5, applied: -5, handler: 0.00004)
        stats.event(time: 0.004, raw: 2, applied: 2, handler: 0.00006)
        stats.tick(timestamp: 0.008, target: 0.016, now: 0.009, position: 3, tracking: true)
        stats.tick(timestamp: 0.016, target: 0.024, now: 0.017, position: 4, tracking: false)
        XCTAssertEqual(stats.latencies.count, 2)
        XCTAssertEqual(stats.latencies[0], 0.014, accuracy: 1e-9)
        XCTAssertEqual(stats.sumRaw, -3)
        XCTAssertEqual(stats.sumApplied, -3)
        XCTAssertEqual(stats.eventHz, 500, accuracy: 1e-9)
    }

    @MainActor func testDisabledAPIsDoNotAccumulate() throws {
        guard !FrameMeter.enabled else { throw XCTSkip("Requires the default disabled environment") }
        FrameMeter.begin(time: 0, mode: "test")
        FrameMeter.noteBody(.paged)
        FrameMeter.noteEvent(time: 0.01, raw: 1, applied: 1, handler: 1)
        FrameMeter.noteTick(timestamp: 0.01, target: 0.02, now: 0.011)
        FrameMeter.endTracking(time: 0.02)
        FrameMeter.noteShow(duration: 1)
        FrameMeter.finish(time: 0.03, velocity: 1)
        XCTAssertNil(FrameMeter.stats)
    }
}
