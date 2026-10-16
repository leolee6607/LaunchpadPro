import Foundation
import QuartzCore
import os

/// Value-only measurements, also usable with synthetic clocks in tests.
struct FrameStats {
    var ticks = 0
    var intervals: [Double] = []
    var lateness: [Double] = []
    var latencies: [Double] = []
    var handlers: [Double] = []
    var eventTimes: [Double] = []
    var displacements: [Double] = []
    var hitches = 0
    var sumRaw = 0.0
    var sumApplied = 0.0
    var bodies = [0, 0, 0]
    private var previousTick: Double?
    private var previousPosition: Double?
    private var pendingEvents: [Double] = []

    var hz: Double { intervals.isEmpty ? 0 : Double(intervals.count) / intervals.reduce(0, +) }
    var eventHz: Double {
        guard let first = eventTimes.first, let last = eventTimes.last, last > first else { return 0 }
        return Double(eventTimes.count - 1) / (last - first)
    }
    var judderCV: Double {
        guard !displacements.isEmpty else { return 0 }
        let mean = displacements.reduce(0, +) / Double(displacements.count)
        guard mean > 0 else { return 0 }
        let variance = displacements.reduce(0) { $0 + pow($1 - mean, 2) } / Double(displacements.count)
        return sqrt(variance) / mean
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * min(1, max(0, fraction))
        let lower = Int(position)
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    mutating func event(time: Double, raw: Double, applied: Double, handler: Double) {
        eventTimes.append(time)
        pendingEvents.append(time)
        sumRaw += raw
        sumApplied += applied
        handlers.append(handler)
    }

    mutating func tick(timestamp: Double, target: Double, now: Double, position: Double, tracking: Bool) {
        ticks += 1
        if let previousTick, timestamp > previousTick {
            let interval = timestamp - previousTick
            intervals.append(interval)
            if interval > 1.5 * (target - timestamp) { hitches += 1 }
        }
        lateness.append(max(0, now - timestamp))
        for event in pendingEvents { latencies.append(max(0, target - event)) }
        pendingEvents.removeAll(keepingCapacity: true)
        if tracking, let previousPosition { displacements.append(abs(position - previousPosition)) }
        previousPosition = tracking ? position : nil
        previousTick = timestamp
    }
}

@MainActor
enum FrameMeter {
    enum Body: Int { case root, paged, strip }
    static let enabled = ProcessInfo.processInfo.environment["LAUNCHPADPRO_FRAMEMETER"] == "1"
    private static let logger = Logger(subsystem: "com.leo.launchpadprocodex", category: "framemeter")
    private(set) static var stats: FrameStats?
    private static var sequence = 0
    private static var mode = "legacy"
    private static var started = 0.0
    private static var released: Double?
    private static var startPage = 0
    private static var lastPage = 0
    private static var position = 0.0
    private static var showMilliseconds = 0.0

    static func begin(time: Double, mode: String, page: Int? = nil) {
        guard enabled else { return }
        if stats != nil { finish(time: time, page: lastPage, velocity: 0) }
        sequence += 1
        self.mode = mode
        started = time
        released = nil
        startPage = page ?? lastPage
        stats = FrameStats()
    }

    static func noteBody(_ body: Body) {
        guard enabled else { return }
        stats?.bodies[body.rawValue] += 1
    }

    static func noteLegacyPosition(page: Int, offset: CGFloat, width: CGFloat) {
        guard enabled else { return }
        lastPage = page
        position = Double(CGFloat(page) * width - offset)
    }

    static func noteEvent(time: Double, raw: CGFloat, applied: CGFloat, handler: Double) {
        guard enabled else { return }
        stats?.event(time: time, raw: Double(raw), applied: Double(applied), handler: handler)
    }

    static func noteTick(timestamp: Double, target: Double, now: Double, stripX: CGFloat? = nil) {
        guard enabled else { return }
        stats?.tick(timestamp: timestamp, target: target, now: now,
                    position: stripX.map(Double.init) ?? position, tracking: released == nil)
    }

    static func endTracking(time: Double) {
        guard enabled else { return }
        released = time
    }

    static func noteShow(duration: Double) {
        guard enabled else { return }
        showMilliseconds = duration * 1_000
    }

    static func finish(time: Double, page: Int? = nil, velocity: CGFloat) {
        guard enabled, let stats else { return }
        let end = released ?? time
        func p(_ values: [Double], _ fraction: Double, _ scale: Double = 1) -> Double {
            FrameStats.percentile(values, fraction) * scale
        }
        let line = String(format:
            "[framemeter] #%d mode=%@ track=%.2fs snap=%.2fs ticks=%d hz=%.1f int_p50/p95/max=%.1f/%.1f/%.1fms hitch=%d late_p95=%.1fms ev=%d ev_hz=%.1f handler_p95/max=%.0f/%.0fus sum_raw=%.3f sum_applied=%.3f lat_p50/p95=%.1f/%.1fms judder_cv=%.2f body_root/paged/strip=%d/%d/%d pages=%d→%d v=%.0f show_ms=%.1f",
            sequence, mode, end - started, max(0, time - end), stats.ticks, stats.hz,
            p(stats.intervals, 0.5, 1_000), p(stats.intervals, 0.95, 1_000), p(stats.intervals, 1, 1_000),
            stats.hitches, p(stats.lateness, 0.95, 1_000), stats.eventTimes.count, stats.eventHz,
            p(stats.handlers, 0.95, 1_000_000), p(stats.handlers, 1, 1_000_000), stats.sumRaw, stats.sumApplied,
            p(stats.latencies, 0.5, 1_000), p(stats.latencies, 0.95, 1_000), stats.judderCV,
            stats.bodies[0], stats.bodies[1], stats.bodies[2], startPage + 1, (page ?? lastPage) + 1,
            Double(velocity), showMilliseconds)
        FileHandle.standardError.write(Data((line + "\n").utf8))
        logger.info("\(line, privacy: .public)")
        self.stats = nil
    }
}
