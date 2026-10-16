import Foundation
import CoreGraphics

struct PagerTuning {
    var gain: CGFloat = 1
    var axisLockDistance: CGFloat = 3
    var velocityWindow: TimeInterval = 0.05
    var staleVelocityAfter: TimeInterval = 0.05
    var distanceFlipFraction: CGFloat = 0.13
    var flickVelocity: CGFloat = 300
    var flickMinDisplacement: CGFloat = 4
    var opposingVeto: CGFloat = 150
    var rubberBandMinimum: CGFloat = 96
    var rubberBandWidthFraction: CGFloat = 0.30
    var mass: CGFloat = 1
    var stiffness: CGFloat = 320
    var dampingRatio: CGFloat = 1
    var positionTolerance: CGFloat = 0.25
    var velocityTolerance: CGFloat = 2
    var predictionMaxAge: TimeInterval = 0.03

    func rubberBandLimit(pageWidth: CGFloat) -> CGFloat {
        max(rubberBandMinimum, rubberBandWidthFraction * pageWidth)
    }
}

struct RubberBand {
    let limit: CGFloat

    func apply(_ distance: CGFloat) -> CGFloat {
        limit * distance / (limit + distance)
    }

    func invert(_ displacement: CGFloat) -> CGFloat {
        limit * displacement / (limit - displacement)
    }

    func derivative(at distance: CGFloat) -> CGFloat {
        let ratio = limit / (limit + distance)
        return ratio * ratio
    }
}

struct VelocityEstimator {
    private struct Sample {
        var time: TimeInterval
        var position: CGFloat
    }

    let window: TimeInterval
    let staleAfter: TimeInterval
    private var samples: [Sample] = []
    private var lastMovementTime: TimeInterval?

    init(tuning: PagerTuning = .init()) {
        window = tuning.velocityWindow
        staleAfter = tuning.staleVelocityAfter
    }

    mutating func reset(position: CGFloat, time: TimeInterval) {
        samples = [Sample(time: time, position: position)]
        lastMovementTime = nil
    }

    mutating func record(position: CGFloat, time: TimeInterval) {
        if let last = samples.last {
            guard time >= last.time else { return }
            if position != last.position { lastMovementTime = time }
            if time == last.time {
                samples[samples.count - 1].position = position
                return
            }
        }
        samples.append(Sample(time: time, position: position))
        // Retain a previous point for the two-sample fallback across a sparse interval.
        while samples.count > 2, samples[0].time < time - window {
            samples.removeFirst()
        }
    }

    func velocity(at time: TimeInterval) -> CGFloat {
        guard let lastMovementTime, time - lastMovementTime <= staleAfter,
              let last = samples.last, samples.count >= 2 else { return 0 }
        let recent = samples.filter { $0.time >= last.time - window }
        guard let first = recent.first, recent.count >= 2,
              last.time - first.time >= 0.008 else {
            let previous = samples[samples.count - 2]
            let interval = last.time - previous.time
            return interval > 0 ? (last.position - previous.position) / CGFloat(interval) : 0
        }

        // Subtract an origin before fitting to retain precision at system uptime timestamps.
        let count = CGFloat(recent.count)
        let meanTime = recent.reduce(CGFloat.zero) { $0 + CGFloat($1.time - first.time) } / count
        let meanPosition = recent.reduce(CGFloat.zero) { $0 + ($1.position - first.position) } / count
        var covariance: CGFloat = 0
        var variance: CGFloat = 0
        for sample in recent {
            let dt = CGFloat(sample.time - first.time) - meanTime
            covariance += dt * (sample.position - first.position - meanPosition)
            variance += dt * dt
        }
        return variance > 0 ? covariance / variance : 0
    }
}

enum PageDecision {
    static func target(startPage: Int, displacement: CGFloat, velocity: CGFloat,
                       pageWidth: CGFloat, pageCount: Int, tuning: PagerTuning = .init()) -> Int {
        let direction = displacement > 0 ? 1 : displacement < 0 ? -1 : 0
        let followsDistance = abs(displacement) >= tuning.distanceFlipFraction * pageWidth
            && velocity * CGFloat(direction) > -tuning.opposingVeto
        let isFlick = abs(velocity) >= tuning.flickVelocity
            && abs(displacement) >= tuning.flickMinDisplacement
            && velocity * CGFloat(direction) > 0
        let step = followsDistance || isFlick ? direction : 0
        return min(max(0, startPage + step), max(0, pageCount - 1))
    }
}

struct SnapSpring {
    struct Sample {
        var position: CGFloat
        var velocity: CGFloat
    }

    let from: CGFloat
    let to: CGFloat
    let initialVelocity: CGFloat
    let startTime: TimeInterval
    let tuning: PagerTuning

    init(from: CGFloat, to: CGFloat, velocity: CGFloat, time: TimeInterval,
         tuning: PagerTuning = .init()) {
        self.from = from
        self.to = to
        initialVelocity = velocity
        startTime = time
        self.tuning = tuning
    }

    func sample(at time: TimeInterval) -> Sample {
        let t = CGFloat(max(0, time - startTime))
        let omega = sqrt(tuning.stiffness / tuning.mass)
        let zeta = tuning.dampingRatio
        let displacement = from - to
        let x: CGFloat
        let v: CGFloat
        if abs(zeta - 1) < 1e-8 {
            let b = initialVelocity + omega * displacement
            let decay = exp(-omega * t)
            x = (displacement + b * t) * decay
            v = (initialVelocity - omega * b * t) * decay
        } else if zeta < 1 {
            let decayRate = zeta * omega
            let frequency = omega * sqrt(1 - zeta * zeta)
            let b = (initialVelocity + decayRate * displacement) / frequency
            let wave = displacement * cos(frequency * t) + b * sin(frequency * t)
            let decay = exp(-decayRate * t)
            x = decay * wave
            v = decay * (-decayRate * wave - displacement * frequency * sin(frequency * t)
                         + b * frequency * cos(frequency * t))
        } else {
            let root = sqrt(zeta * zeta - 1)
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            let a = (initialVelocity - r2 * displacement) / (r1 - r2)
            let b = displacement - a
            x = a * exp(r1 * t) + b * exp(r2 * t)
            v = a * r1 * exp(r1 * t) + b * r2 * exp(r2 * t)
        }
        return Sample(position: to + x, velocity: v)
    }

    func isSettled(_ sample: Sample) -> Bool {
        abs(sample.position - to) < tuning.positionTolerance
            && abs(sample.velocity) < tuning.velocityTolerance
    }
}

enum ScrollPhase {
    case mayBegin, began, changed, ended, cancelled, other
}

struct PagerMachine {
    enum Phase { case idle, pendingAxis, tracking, ignoring, caught, snapping }

    let tuning: PagerTuning
    var predictEnabled = false
    private(set) var stripX: CGFloat = 0
    private(set) var targetPage = 0
    private(set) var restingPage = 0
    private(set) var startPage = 0
    private(set) var phase: Phase = .idle
    private(set) var gestureRawDX: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private(set) var pageWidth: CGFloat = 1
    private(set) var pageCount = 1
    private(set) var isLocked = false
    private var rawPosition: CGFloat = 0
    private var pendingDX: CGFloat = 0
    private var pendingDY: CGFloat = 0
    private var estimator: VelocityEstimator
    private var spring: SnapSpring?
    private var lastTime: TimeInterval = 0
    private var lastEventTime: TimeInterval?

    init(tuning: PagerTuning = .init()) {
        self.tuning = tuning
        estimator = VelocityEstimator(tuning: tuning)
    }

    var needsFrames: Bool {
        phase == .pendingAxis || phase == .tracking || phase == .caught || phase == .snapping
    }

    private var maximumPosition: CGFloat { CGFloat(pageCount - 1) * pageWidth }
    private var rubberBand: RubberBand { RubberBand(limit: tuning.rubberBandLimit(pageWidth: pageWidth)) }

    mutating func configure(pageWidth: CGFloat, pageCount: Int) {
        self.pageWidth = max(1, pageWidth)
        self.pageCount = max(1, pageCount)
        targetPage = clamped(targetPage)
        restingPage = clamped(restingPage)
        startPage = clamped(startPage)
        switch phase {
        case .idle:
            jump(to: targetPage)
        case .snapping:
            snap(to: targetPage, velocity: nil, time: lastTime)
        case .pendingAxis, .tracking, .ignoring, .caught:
            break // A geometry update must not interrupt the current gesture.
        }
    }

    mutating func setLocked(_ locked: Bool, time: TimeInterval) {
        guard locked != isLocked else { return }
        isLocked = locked
        lastTime = time
        guard locked else { return }
        switch phase {
        case .pendingAxis, .tracking:
            snap(to: startPage, velocity: 0, time: time)
        case .caught, .ignoring:
            settleNearest(time: time)
        case .idle, .snapping:
            break
        }
    }

    mutating func scroll(dx: CGFloat, dy: CGFloat, phase input: ScrollPhase, time: TimeInterval) {
        guard !isLocked else { return }
        lastTime = time
        switch input {
        case .mayBegin:
            if phase == .snapping {
                rawPosition = undamped(stripX)
                spring = nil
                velocity = 0
                phase = .caught
            }
        case .began:
            guard phase == .idle || phase == .caught || phase == .snapping else { return }
            startPage = phase == .idle ? restingPage : targetPage
            rawPosition = undamped(stripX)
            pendingDX = 0
            pendingDY = 0
            gestureRawDX = 0
            velocity = 0
            spring = nil
            estimator.reset(position: rawPosition, time: time)
            phase = .pendingAxis
            acceptDelta(dx: dx, dy: dy, time: time)
        case .changed:
            acceptDelta(dx: dx, dy: dy, time: time)
        case .ended:
            acceptDelta(dx: dx, dy: dy, time: time)
            if phase == .tracking {
                let rawVelocity = estimator.velocity(at: time)
                let destination = PageDecision.target(
                    startPage: startPage, displacement: rawPosition - CGFloat(startPage) * pageWidth,
                    velocity: rawVelocity, pageWidth: pageWidth, pageCount: pageCount, tuning: tuning)
                snap(to: destination, velocity: rawVelocity * dampingDerivative(rawPosition), time: time)
            } else if phase == .pendingAxis {
                snap(to: startPage, velocity: 0, time: time)
            } else if phase == .caught || phase == .ignoring {
                settleNearest(time: time)
            }
        case .cancelled:
            if phase == .pendingAxis || phase == .tracking {
                snap(to: startPage, velocity: 0, time: time)
            } else if phase == .caught || phase == .ignoring {
                settleNearest(time: time)
            }
        case .other:
            break
        }
    }

    mutating func tick(targetTime: TimeInterval, frameDuration: TimeInterval = 1.0 / 120) {
        lastTime = targetTime
        if phase == .snapping, let spring {
            let sample = spring.sample(at: targetTime)
            stripX = sample.position
            velocity = sample.velocity
            if spring.isSettled(sample) {
                stripX = CGFloat(targetPage) * pageWidth
                rawPosition = stripX
                restingPage = targetPage
                velocity = 0
                self.spring = nil
                phase = .idle
            }
        } else if phase == .tracking, predictEnabled, let lastEventTime {
            let age = max(0, targetTime - lastEventTime)
            let horizon = age <= tuning.predictionMaxAge ? min(age, max(0, frameDuration)) : 0
            stripX = damped(rawPosition + estimator.velocity(at: targetTime) * CGFloat(horizon))
        }
    }

    mutating func snap(to page: Int, velocity initialVelocity: CGFloat? = nil, time: TimeInterval) {
        targetPage = clamped(page)
        velocity = initialVelocity ?? velocity
        spring = SnapSpring(from: stripX, to: CGFloat(targetPage) * pageWidth,
                            velocity: velocity, time: time, tuning: tuning)
        lastTime = time
        phase = .snapping
    }

    mutating func jump(to page: Int) {
        targetPage = clamped(page)
        restingPage = targetPage
        startPage = targetPage
        stripX = CGFloat(targetPage) * pageWidth
        rawPosition = stripX
        velocity = 0
        gestureRawDX = 0
        pendingDX = 0
        pendingDY = 0
        lastEventTime = nil
        spring = nil
        phase = .idle
    }

    private mutating func acceptDelta(dx: CGFloat, dy: CGFloat, time: TimeInterval) {
        guard phase == .pendingAxis || phase == .tracking else { return }
        lastEventTime = time
        if phase == .pendingAxis {
            pendingDX += dx
            pendingDY += dy
            estimator.record(position: rawPosition - pendingDX * tuning.gain, time: time)
            guard hypot(pendingDX, pendingDY) >= tuning.axisLockDistance else { return }
            guard abs(pendingDX) >= abs(pendingDY) else {
                phase = .ignoring
                return
            }
            gestureRawDX = pendingDX
            rawPosition -= pendingDX * tuning.gain
            phase = .tracking
        } else {
            gestureRawDX += dx
            rawPosition -= dx * tuning.gain
            estimator.record(position: rawPosition, time: time)
        }
        stripX = damped(rawPosition)
        velocity = estimator.velocity(at: time) * dampingDerivative(rawPosition)
    }

    private mutating func settleNearest(time: TimeInterval) {
        let page = clamped(Int((stripX / pageWidth).rounded()))
        if stripX == CGFloat(page) * pageWidth {
            jump(to: page)
        } else {
            snap(to: page, velocity: 0, time: time)
        }
    }

    private func clamped(_ page: Int) -> Int { min(max(0, page), pageCount - 1) }

    private func damped(_ raw: CGFloat) -> CGFloat {
        if raw < 0 { return -rubberBand.apply(-raw) }
        if raw > maximumPosition { return maximumPosition + rubberBand.apply(raw - maximumPosition) }
        return raw
    }

    private func undamped(_ display: CGFloat) -> CGFloat {
        if display < 0 { return -rubberBand.invert(-display) }
        if display > maximumPosition { return maximumPosition + rubberBand.invert(display - maximumPosition) }
        return display
    }

    private func dampingDerivative(_ raw: CGFloat) -> CGFloat {
        if raw < 0 { return rubberBand.derivative(at: -raw) }
        if raw > maximumPosition { return rubberBand.derivative(at: raw - maximumPosition) }
        return 1
    }
}
