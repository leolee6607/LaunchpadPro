import AppKit
import Observation
import QuartzCore

@Observable @MainActor
final class PagerState {
    var targetPage = 0
    var restingPage = 0
}

@MainActor
final class PagerController {
    let state = PagerState()
    private var machine = PagerMachine()
    private weak var container: PageStripContainerView?
    private var displayLink: CADisplayLink?
    private lazy var displayLinkTarget = DisplayLinkTarget(pager: self)
    private var releaseVelocity: CGFloat = 0

    init() {
        machine.predictEnabled = ProcessInfo.processInfo.environment["LAUNCHPADPRO_SWIPE_PREDICT"] == "1"
    }

    var isLocked: Bool {
        get { machine.isLocked }
        set {
            guard container != nil else { return }
            let time = CACurrentMediaTime()
            let wasTracking = machine.phase == .pendingAxis || machine.phase == .tracking
            machine.setLocked(newValue, time: time)
            if newValue, wasTracking, FrameMeter.enabled {
                releaseVelocity = 0
                FrameMeter.endTracking(time: time)
            }
            applyMachine(time: time)
        }
    }

    func attach(_ container: PageStripContainerView) {
        if let attached = self.container { detach(attached) }
        self.container = container
        jump(to: 0)
    }

    func detach(_ container: PageStripContainerView) {
        guard self.container === container else { return }
        stop()
        machine.setLocked(false, time: CACurrentMediaTime())
        self.container = nil
    }

    func configure(pageWidth: CGFloat, pageCount: Int) {
        guard container != nil else { return }
        machine.configure(pageWidth: pageWidth, pageCount: pageCount)
        applyMachine(time: CACurrentMediaTime())
    }

    func handleScroll(_ event: NSEvent) {
        // Momentum belongs to the OS scroll animation, not this gesture's raw displacement.
        guard !event.phase.isEmpty || event.momentumPhase.isEmpty else { return }
        handleScroll(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                     phase: Self.scrollPhase(event.phase), time: event.timestamp)
    }

    func handleScroll(dx: CGFloat, dy: CGFloat, phase: ScrollPhase, time: TimeInterval) {
        guard container != nil, !machine.isLocked else { return }
        let handlerStart = FrameMeter.enabled ? CACurrentMediaTime() : 0
        let startingGesture = phase == .began
            && (machine.phase == .idle || machine.phase == .caught || machine.phase == .snapping)
        if FrameMeter.enabled, startingGesture {
            FrameMeter.finish(time: time, page: machine.targetPage, velocity: releaseVelocity)
            FrameMeter.begin(time: time, mode: machine.predictEnabled ? "predict" : "direct",
                             page: machine.phase == .idle ? machine.restingPage : machine.targetPage)
            releaseVelocity = 0
        }
        let previousDX = startingGesture ? 0 : machine.gestureRawDX
        machine.scroll(dx: dx, dy: dy, phase: phase, time: time)
        // Commit geometry in the event's call stack, before the next runloop/CA commit.
        container?.setStripX(machine.stripX)
        updateDisplayLink()
        if FrameMeter.enabled {
            if phase == .ended || phase == .cancelled {
                releaseVelocity = machine.velocity
                FrameMeter.endTracking(time: time)
            }
            FrameMeter.noteEvent(time: time, raw: dx, applied: machine.gestureRawDX - previousDX,
                                 handler: CACurrentMediaTime() - handlerStart)
        }
        finishMeasurementsIfIdle(time: time)
        publishState()
    }

    func snap(to page: Int, velocity: CGFloat? = nil) {
        guard container != nil else { return }
        let time = CACurrentMediaTime()
        if FrameMeter.enabled, machine.phase == .pendingAxis || machine.phase == .tracking {
            FrameMeter.endTracking(time: time)
        }
        machine.snap(to: page, velocity: velocity, time: time)
        applyMachine(time: time)
    }

    func step(by delta: Int) {
        snap(to: machine.targetPage + delta, velocity: 0)
    }

    func jump(to page: Int) {
        guard container != nil else { return }
        machine.jump(to: page)
        applyMachine(time: CACurrentMediaTime())
    }

    func reset() { jump(to: 0) }
    func stop() { jump(to: machine.targetPage) }

    func viewportPoint(fromStrip point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - machine.stripX, y: point.y)
    }

    func stripPoint(fromViewport point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + machine.stripX, y: point.y)
    }

    func viewportRect(fromStrip rect: CGRect) -> CGRect {
        CGRect(origin: viewportPoint(fromStrip: rect.origin), size: rect.size)
    }

    private static func scrollPhase(_ phase: NSEvent.Phase) -> ScrollPhase {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.mayBegin) { return .mayBegin }
        return .other
    }

    private func applyMachine(time: TimeInterval) {
        container?.setStripX(machine.stripX)
        finishMeasurementsIfIdle(time: time)
        publishState()
        updateDisplayLink()
    }

    private func publishState() {
        if state.targetPage != machine.targetPage { state.targetPage = machine.targetPage }
        let restingPage: Int
        if machine.phase == .idle {
            restingPage = machine.restingPage
        } else if abs(machine.targetPage - state.restingPage) >= 2 {
            restingPage = machine.targetPage
        } else {
            // Keep an early window shift until settlement, even across interrupted snaps.
            restingPage = min(state.restingPage, machine.pageCount - 1)
        }
        if state.restingPage != restingPage { state.restingPage = restingPage }
    }

    private func finishMeasurementsIfIdle(time: TimeInterval) {
        guard FrameMeter.enabled, machine.phase == .idle else { return }
        // Finish before restingPage invalidates any SwiftUI observation.
        FrameMeter.finish(time: time, page: machine.restingPage, velocity: releaseVelocity)
    }

    private func updateDisplayLink() {
        guard machine.needsFrames, let container else {
            displayLink?.invalidate()
            displayLink = nil
            return
        }
        guard displayLink == nil else { return }
        let link = container.displayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.fired(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func displayLinkFired(_ link: CADisplayLink) {
        advanceFrame(timestamp: link.timestamp, targetTimestamp: link.targetTimestamp,
                     now: FrameMeter.enabled ? CACurrentMediaTime() : 0)
    }

    func advanceFrame(timestamp: TimeInterval, targetTimestamp: TimeInterval, now: TimeInterval) {
        guard container != nil else { return }
        let writesPosition = machine.phase == .snapping || (machine.phase == .tracking && machine.predictEnabled)
        machine.tick(targetTime: targetTimestamp, frameDuration: targetTimestamp - timestamp)
        if writesPosition { container?.setStripX(machine.stripX) }
        if FrameMeter.enabled {
            FrameMeter.noteTick(timestamp: timestamp, target: targetTimestamp, now: now, stripX: machine.stripX)
        }
        finishMeasurementsIfIdle(time: targetTimestamp)
        publishState()
        updateDisplayLink()
    }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
    weak var pager: PagerController?

    init(pager: PagerController) { self.pager = pager }

    @objc func fired(_ link: CADisplayLink) {
        guard let pager else {
            link.invalidate()
            return
        }
        pager.displayLinkFired(link)
    }
}
