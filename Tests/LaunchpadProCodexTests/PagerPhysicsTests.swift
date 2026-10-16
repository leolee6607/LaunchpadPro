import XCTest
@testable import LaunchpadProCodex

final class PagerPhysicsTests: XCTestCase {
    func testTuningDefaults() {
        let tuning = PagerTuning()
        XCTAssertEqual(tuning.gain, 1)
        XCTAssertEqual(tuning.axisLockDistance, 3)
        XCTAssertEqual(tuning.velocityWindow, 0.05)
        XCTAssertEqual(tuning.staleVelocityAfter, 0.05)
        XCTAssertEqual(tuning.rubberBandLimit(pageWidth: 100), 96)
        XCTAssertEqual(tuning.rubberBandLimit(pageWidth: 1500), 450)
        XCTAssertEqual(tuning.mass, 1)
        XCTAssertEqual(tuning.stiffness, 320)
        XCTAssertEqual(tuning.dampingRatio, 1)
    }

    func testVelocityWithTimestampJitterAtAllRequiredRates() {
        for rate in [60, 90, 120, 125, 240] {
            for seed in 1...20 {
                var random = PhysicsRandom(seed: UInt64(seed))
                var estimator = VelocityEstimator()
                let origin = 123_456.0
                estimator.reset(position: 0, time: origin)
                var lastTime = origin
                for index in 1...rate {
                    let actualTime = Double(index) / Double(rate)
                    lastTime = origin + actualTime + random.signedUnit() * 0.001
                    estimator.record(position: CGFloat(1000 * actualTime), time: lastTime)
                    if actualTime >= 0.1 {
                        let tolerance: CGFloat = rate == 60 ? 80 : 50
                        XCTAssertEqual(estimator.velocity(at: lastTime), 1000, accuracy: tolerance,
                                       "rate=\(rate), seed=\(seed), sample=\(index)")
                    }
                }
            }
        }
    }

    func testStaleVelocityAndReversal() {
        var estimator = VelocityEstimator()
        estimator.reset(position: 0, time: 0)
        for index in 1...20 {
            estimator.record(position: CGFloat(index * 10), time: Double(index) * 0.01)
        }
        XCTAssertEqual(estimator.velocity(at: 0.2), 1000, accuracy: 1e-6)
        XCTAssertLessThan(abs(estimator.velocity(at: 0.26)), 50)
        var stopped = estimator
        stopped.record(position: 200, time: 0.26)
        XCTAssertEqual(stopped.velocity(at: 0.26), 0)
        for index in 1...4 {
            estimator.record(position: CGFloat(200 - index * 20), time: 0.2 + Double(index) * 0.01)
        }
        XCTAssertLessThan(estimator.velocity(at: 0.24), -1000)
    }

    func testVelocityFallbackAndRepeatedTimestamps() {
        var estimator = VelocityEstimator()
        estimator.reset(position: 0, time: 0)
        XCTAssertEqual(estimator.velocity(at: 0), 0)
        estimator.record(position: 2, time: 0.002)
        XCTAssertEqual(estimator.velocity(at: 0.002), 1000, accuracy: 1e-6)
        estimator.record(position: 3, time: 0.002)
        XCTAssertEqual(estimator.velocity(at: 0.002), 1500, accuracy: 1e-6)
        estimator.record(position: 999, time: 0.001)
        XCTAssertEqual(estimator.velocity(at: 0.002), 1500, accuracy: 1e-6)
        estimator.record(position: 103, time: 0.102)
        XCTAssertEqual(estimator.velocity(at: 0.102), 1000, accuracy: 1e-6)
        estimator.reset(position: 0, time: 1)
        XCTAssertEqual(estimator.velocity(at: 1), 0)
    }

    func testPageDecisionTable() {
        let cases: [(Int, CGFloat, CGFloat, Int)] = [
            (1, 100, 0, 1), (1, 200, 0, 2), (1, 10, 400, 2),
            (1, 600, -400, 1), (1, 3, 400, 1), (1, 1400, 3000, 2),
            (2, 300, 800, 2), (0, -300, 0, 0),
            (1, -200, 0, 0), (1, -10, -400, 0), (1, -600, 400, 1),
            (1, 195, -150, 1), (1, 195, -149, 2),
            (1, 4, 300, 2), (1, 4, 299, 1), (1, 0, 1000, 1)
        ]
        for (start, displacement, velocity, expected) in cases {
            XCTAssertEqual(PageDecision.target(startPage: start, displacement: displacement,
                                               velocity: velocity, pageWidth: 1500, pageCount: 3), expected,
                           "start=\(start), d=\(displacement), v=\(velocity)")
        }
    }

    func testRubberBandMonotonicBoundedAndInvertible() {
        for limit: CGFloat in [96, 450] {
            let band = RubberBand(limit: limit)
            var previous: CGFloat = -1
            for step in 0...1000 {
                let x = CGFloat(step) / 1000 * 5 * limit
                let display = band.apply(x)
                XCTAssertGreaterThan(display, previous)
                XCTAssertLessThan(display, limit)
                XCTAssertEqual(band.invert(display), x, accuracy: 1e-6)
                let epsilon: CGFloat = 0.0001
                let slope = (band.apply(x + epsilon) - display) / epsilon
                XCTAssertEqual(band.derivative(at: x), slope, accuracy: 2e-6)
                previous = display
            }
        }
    }

    func testSpringInitialPositionAndVelocity() {
        for damping: CGFloat in [0.7, 1, 1.5] {
            var tuning = PagerTuning()
            tuning.dampingRatio = damping
            for velocity: CGFloat in [-6000, 0, 6000] {
                let spring = SnapSpring(from: 345, to: 1512, velocity: velocity, time: 10, tuning: tuning)
                let initial = spring.sample(at: 10)
                XCTAssertEqual(initial.position, 345, accuracy: 1e-9)
                XCTAssertEqual(initial.velocity, velocity, accuracy: 1e-9)
                let next = spring.sample(at: 10.000001)
                XCTAssertEqual((next.position - initial.position) / 0.000001, velocity, accuracy: 1)
            }
        }
    }

    func testZeroVelocitySpringConvergesMonotonicallyWithoutOvershoot() {
        for direction: CGFloat in [-1, 1] {
            let destination = direction * 1512
            let spring = SnapSpring(from: 0, to: destination, velocity: 0, time: 0)
            var previous: CGFloat = 0
            for step in 1...700 {
                let sample = spring.sample(at: Double(step) / 1000)
                XCTAssertGreaterThanOrEqual(direction * sample.position, direction * previous)
                XCTAssertLessThanOrEqual(direction * sample.position, 1512)
                previous = sample.position
            }
            XCTAssertTrue(spring.isSettled(spring.sample(at: 0.7)))
        }
    }

    func testPageSpringOvershootAndSettlingAtRequiredVelocities() {
        let width: CGFloat = 1512
        for direction: CGFloat in [-1, 1] {
            for speed in stride(from: -6000, through: 6000, by: 250) {
                let spring = SnapSpring(from: 0, to: direction * width, velocity: CGFloat(speed), time: 0)
                for step in 0...700 {
                    let position = direction * spring.sample(at: Double(step) / 1000).position
                    let overshoot = max(0, -position, position - width)
                    XCTAssertLessThanOrEqual(overshoot, 0.04 * width)
                }
                XCTAssertTrue(spring.isSettled(spring.sample(at: 0.7)), "velocity=\(speed)")
            }
        }
    }
}

struct PhysicsRandom {
    var seed: UInt64

    mutating func signedUnit() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(UInt64.max >> 11) * 2 - 1
    }
}
