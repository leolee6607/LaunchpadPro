import AppKit
import Observation
import QuartzCore
import SwiftUI
import XCTest
@testable import LaunchpadProCodex

final class PageStripViewTests: XCTestCase {
    func testLayoutSignatureTracksPreviewAndReleaseWithUnchangedOrder() {
        let original: [[LaunchEntry]] = [[.app("a"), .app("b"), .app("c")]]
        let preview: [[LaunchEntry]] = [[.app("b"), .app("c"), .app("a")]]
        let dragging = PageStripLayoutSignature(pages: original, draggingID: "app:a")
        let yielding = PageStripLayoutSignature(pages: preview, draggingID: "app:a")
        let released = PageStripLayoutSignature(pages: preview, draggingID: nil)

        XCTAssertNotEqual(dragging, yielding)
        XCTAssertEqual(yielding.entryIDs, released.entryIDs)
        XCTAssertNotEqual(yielding, released)
        XCTAssertEqual(released, PageStripLayoutSignature(pages: preview, draggingID: nil))
    }

    func testLayoutSignatureTracksFolderMergeAndPageBoundaries() {
        let folder = FolderRecord(id: "folder", name: "Tools", appIDs: ["b", "c"])
        let before = PageStripLayoutSignature(pages: [[.app("a"), .folder(folder), .app("d")]],
                                             draggingID: "app:a")
        let merged = PageStripLayoutSignature(pages: [[.folder(folder), .app("d")]], draggingID: nil)
        let split = PageStripLayoutSignature(pages: [[.folder(folder)], [.app("d")]], draggingID: nil)

        XCTAssertNotEqual(before, merged)
        XCTAssertEqual(merged.entryIDs.flatMap { $0 }, split.entryIDs.flatMap { $0 })
        XCTAssertNotEqual(merged, split)
        let renamed = FolderRecord(id: "folder", name: "Renamed", appIDs: ["a", "b", "c"])
        XCTAssertEqual(merged, PageStripLayoutSignature(pages: [[.folder(renamed), .app("d")]], draggingID: nil))
    }

    func testLayoutSignatureDoesNotDependOnPageWindow() {
        let pages: [[LaunchEntry]] = (0..<8).map { [.app("\($0)")] }
        let entries = pages.enumerated().map { PlacedEntry(page: $0.offset, index: 0, entry: $0.element[0]) }
        let signature = PageStripLayoutSignature(pages: pages, draggingID: nil)
        let firstWindow = PageStripWindow.entries(from: entries, activeLocations: [:],
                                                  restingPage: 0, draggingID: nil)
        let lastWindow = PageStripWindow.entries(from: entries, activeLocations: [:],
                                                 restingPage: 7, draggingID: nil)

        XCTAssertNotEqual(firstWindow.map(\.id), lastWindow.map(\.id))
        XCTAssertEqual(signature, PageStripLayoutSignature(pages: pages, draggingID: nil))
    }

    @MainActor func testHostingRootReplacementAnimatesPreviewReleaseAndMerge() {
        let flow = Animation.spring(response: 0.24, dampingFraction: 0.80)
        let layouts = [
            PageStripLayoutSignature(pages: [[.app("a"), .app("b"), .app("c")]], draggingID: "app:a"),
            PageStripLayoutSignature(pages: [[.app("b"), .app("a"), .app("c")]], draggingID: "app:a"),
            PageStripLayoutSignature(pages: [[.app("b"), .app("a"), .app("c")]], draggingID: nil),
            PageStripLayoutSignature(pages: [[.folder(FolderRecord(id: "f", name: "F", appIDs: ["a", "b"])), .app("c")]],
                                     draggingID: nil)
        ]
        var observed: [Animation?] = []
        func probe(_ index: Int) -> LayoutAnimationProbe {
            LayoutAnimationProbe(signature: layouts[index], transaction: Transaction(animation: flow),
                                 position: CGFloat(index * 20), record: { observed.append($0.animation) })
        }
        let host = NSHostingView(rootView: probe(0))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        // SwiftUI may omit the transaction callback on an unanimated initial layout.
        XCTAssertTrue(observed.allSatisfy { $0 == nil }, "First display must not animate")

        for index in 1..<layouts.count {
            observed.removeAll()
            host.rootView = probe(index)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(observed.contains { $0 == flow }, "Layout change \(index) must animate inside the hosting tree")
        }
    }

    @MainActor func testOuterTransactionAloneDoesNotAnimateHostingRootReplacement() {
        let original = PageStripLayoutSignature(pages: [[.app("a"), .app("b")]], draggingID: "app:a")
        let changed = PageStripLayoutSignature(pages: [[.app("b"), .app("a")]], draggingID: "app:a")
        var observed: [Animation?] = []
        let host = NSHostingView(rootView: LayoutAnimationProbe(
            signature: original, transaction: Transaction(), position: 0, bridgeEnabled: false,
            record: { observed.append($0.animation) }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        observed.removeAll()
        withTransaction(Transaction(animation: .spring(response: 0.24, dampingFraction: 0.80))) {
            host.rootView = LayoutAnimationProbe(signature: changed, transaction: Transaction(), position: 100,
                                                 bridgeEnabled: false, record: { observed.append($0.animation) })
        }
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(observed.isEmpty)
        XCTAssertTrue(observed.allSatisfy { $0 == nil })
    }

    @MainActor func testUnchangedSignatureDoesNotAnimateUnrelatedUpdates() {
        let signature = PageStripLayoutSignature(pages: [[.app("a"), .app("b")]], draggingID: nil)
        let transaction = Transaction(animation: .spring(response: 0.24, dampingFraction: 0.80))
        var observed: [Animation?] = []
        let host = NSHostingView(rootView: LayoutAnimationProbe(
            signature: signature, transaction: transaction, position: 0,
            record: { observed.append($0.animation) }
        ))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        observed.removeAll()
        host.rootView = LayoutAnimationProbe(signature: signature, transaction: transaction, position: 100,
                                             record: { observed.append($0.animation) })
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(observed.isEmpty)
        XCTAssertTrue(observed.allSatisfy { $0 == nil })
    }

    @MainActor func testHostingLayoutChangesWithoutAnimationOrWithDisabledAnimationsStayImmediate() {
        let original = PageStripLayoutSignature(pages: [[.app("a"), .app("b")]], draggingID: nil)
        let changed = PageStripLayoutSignature(pages: [[.app("b")], [.app("a")]], draggingID: nil)
        var disabled = Transaction(animation: .spring(response: 0.24, dampingFraction: 0.80))
        disabled.disablesAnimations = true

        for transaction in [Transaction(), disabled] {
            var observed: [Animation?] = []
            let host = NSHostingView(rootView: LayoutAnimationProbe(
                signature: original, transaction: Transaction(), position: 0,
                record: { observed.append($0.animation) }
            ))
            host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
            host.layoutSubtreeIfNeeded()
            observed.removeAll()
            host.rootView = LayoutAnimationProbe(signature: changed, transaction: transaction, position: 100,
                                                 record: { observed.append($0.animation) })
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(observed.isEmpty)
            XCTAssertTrue(observed.allSatisfy { $0 == nil })
        }
    }

    func testWindowIncludesTwoNeighborPagesAndClipsAtEnds() {
        let entries = (0..<8).flatMap { page in
            (0..<2).map { index in
                PlacedEntry(page: page, index: index, entry: .app("\(page)-\(index)"))
            }
        }
        for (restingPage, expectedPages) in [(0, [0, 1, 2]), (3, [1, 2, 3, 4, 5]), (7, [5, 6, 7])] {
            let visible = PageStripWindow.entries(from: entries, activeLocations: [:],
                                                  restingPage: restingPage, draggingID: nil)
            XCTAssertEqual(visible.map(\.id), expectedPages.flatMap { page in
                ["app:\(page)-0", "app:\(page)-1"]
            })
        }
        XCTAssertTrue(PageStripWindow.entries(from: [], activeLocations: [:],
                                               restingPage: 0, draggingID: nil).isEmpty)
    }

    func testWindowIncludesOriginalAndPreviewLocationsWithoutMovingEntries() {
        let entries = [
            PlacedEntry(page: 0, index: 1, entry: .app("moved-out")),
            PlacedEntry(page: 5, index: 2, entry: .app("moved-in")),
            PlacedEntry(page: 6, index: 0, entry: .app("outside"))
        ]
        let active: [String: (page: Int, index: Int)] = [
            "app:moved-out": (5, 0), "app:moved-in": (2, 0), "app:outside": (7, 0)
        ]
        let visible = PageStripWindow.entries(from: entries, activeLocations: active,
                                              restingPage: 0, draggingID: nil)
        XCTAssertEqual(visible.map(\.id), ["app:moved-out", "app:moved-in"])
        XCTAssertEqual(visible.map(\.page), [0, 5])
        XCTAssertEqual(visible.map(\.index), [1, 2])
    }

    func testDraggedEntrySurvivesWindowChangesEvenOutsidePreviewWindow() {
        let entries = (0..<10).map { PlacedEntry(page: $0, index: 0, entry: .app("\($0)")) }
        let active: [String: (page: Int, index: Int)] = ["app:0": (1, 0)]
        for restingPage in [0, 3, 6, 9] {
            let visible = PageStripWindow.entries(from: entries, activeLocations: active,
                                                  restingPage: restingPage, draggingID: "app:0")
            XCTAssertEqual(visible.filter { $0.id == "app:0" }.count, 1)
            XCTAssertEqual(visible.first?.page, 0)
        }
        let released = PageStripWindow.entries(from: entries, activeLocations: active,
                                               restingPage: 9, draggingID: nil)
        XCTAssertEqual(released.map(\.id), ["app:7", "app:8", "app:9"])
        XCTAssertTrue(PageStripWindow.entries(from: [], activeLocations: active,
                                               restingPage: 0, draggingID: "app:0").isEmpty)
    }

    @MainActor func testConsecutiveSwipesAdvanceWindowOnceAndKeepItUntilSettlement() {
        for direction in [-1, 1] {
            let start = direction == 1 ? 0 : 5
            let pager = PagerController()
            let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
            pager.attach(container)
            defer { pager.detach(container) }
            pager.configure(pageWidth: 1500, pageCount: 6)
            pager.jump(to: start)
            pager.handleScroll(dx: 0, dy: 0, phase: .began, time: 10)
            pager.handleScroll(dx: CGFloat(-direction * 400), dy: 0, phase: .ended, time: 10.1)
            XCTAssertEqual(pager.state.targetPage, start + direction)
            XCTAssertEqual(pager.state.restingPage, start)
            pager.advanceFrame(timestamp: 10.27, targetTimestamp: 10.28, now: 10.27)
            pager.handleScroll(dx: 0, dy: 0, phase: .began, time: 10.28)
            let beforeSecondRelease = container.bounds.origin.x
            pager.handleScroll(dx: CGFloat(-direction * 500), dy: 0, phase: .ended, time: 10.38)
            XCTAssertEqual(pager.state.targetPage, start + direction * 2)
            XCTAssertEqual(pager.state.restingPage, start + direction * 2)
            XCTAssertEqual(container.bounds.origin.x, beforeSecondRelease + CGFloat(direction * 500), accuracy: 1e-6)

            let changes = ObservationCount()
            withObservationTracking {
                _ = pager.state.restingPage
            } onChange: {
                changes.value += 1
            }
            for frame in 1...5 {
                let timestamp = 10.38 + Double(frame) / 120
                pager.advanceFrame(timestamp: timestamp, targetTimestamp: timestamp + 1 / 120, now: timestamp)
            }
            pager.handleScroll(dx: 0, dy: 0, phase: .mayBegin, time: 10.44)
            pager.handleScroll(dx: 0, dy: 0, phase: .began, time: 10.45)
            pager.handleScroll(dx: CGFloat(-direction * 10), dy: 0, phase: .changed, time: 10.46)
            pager.handleScroll(dx: 0, dy: 0, phase: .cancelled, time: 10.47)
            pager.advanceFrame(timestamp: 11.49, targetTimestamp: 11.5, now: 11.49)
            XCTAssertEqual(pager.state.restingPage, start + direction * 2)
            XCTAssertEqual(container.bounds.origin.x, CGFloat(start + direction * 2) * 1500)
            XCTAssertEqual(changes.value, 0)

            pager.handleScroll(dx: 0, dy: 0, phase: .began, time: 12)
            pager.handleScroll(dx: CGFloat(direction * 400), dy: 0, phase: .ended, time: 12.1)
            XCTAssertEqual(pager.state.targetPage, start + direction)
            XCTAssertEqual(pager.state.restingPage, start + direction * 2)
            pager.advanceFrame(timestamp: 13.09, targetTimestamp: 13.1, now: 13.09)
            XCTAssertEqual(pager.state.restingPage, start + direction)
            XCTAssertEqual(changes.value, 1)
        }
    }

    @MainActor func testEarlyWindowShiftHandlesCommandsAndPageCountReduction() {
        let pager = PagerController()
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        pager.attach(container)
        defer { pager.detach(container) }
        pager.configure(pageWidth: 1500, pageCount: 6)
        pager.snap(to: 5, velocity: 0)
        XCTAssertEqual(pager.state.restingPage, 5)
        XCTAssertEqual(container.bounds.origin.x, 0)
        let time = CACurrentMediaTime()
        pager.advanceFrame(timestamp: time + 0.09, targetTimestamp: time + 0.1, now: time + 0.09)
        XCTAssertEqual(pager.state.restingPage, 5)
        pager.configure(pageWidth: 1500, pageCount: 5)
        XCTAssertEqual(pager.state.targetPage, 4)
        XCTAssertEqual(pager.state.restingPage, 4)
        pager.configure(pageWidth: 1500, pageCount: 2)
        XCTAssertEqual(pager.state.targetPage, 1)
        XCTAssertEqual(pager.state.restingPage, 1)
        pager.stop()
        XCTAssertEqual(container.bounds.origin.x, 1500)
        pager.reset()
        XCTAssertEqual(pager.state.restingPage, 0)
        XCTAssertEqual(container.bounds.origin.x, 0)
    }

    @MainActor func testSecondPageHitUsesShiftedBoundsAndParentCoordinates() {
        let parent = FlippedTestView(frame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let container = PageStripContainerView(frame: CGRect(x: 40, y: 30, width: 1500, height: 800))
        let entry = NSView(frame: CGRect(x: 1500, y: 100, width: 30, height: 30))
        parent.addSubview(container)
        container.addSubview(entry)
        container.setStripX(1500)

        XCTAssertTrue(container.hitTest(CGPoint(x: 50, y: 140)) === entry)
        XCTAssertEqual(entry.convert(CGPoint(x: 10, y: 10), to: parent).x, 50)
        XCTAssertNil(container.hitTest(CGPoint(x: 39, y: 140)))
        XCTAssertNil(container.hitTest(CGPoint(x: 1541, y: 140)))
        XCTAssertTrue(container.isFlipped)
        XCTAssertTrue(container.clipsToBounds)
        XCTAssertTrue(container.wantsLayer)
        XCTAssertTrue(container.wantsUpdateLayer)
        XCTAssertEqual(container.layerContentsRedrawPolicy, .never)
    }

    @MainActor func testDisabledHitTestingAndViewportExclusions() {
        let parent = FlippedTestView(frame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let container = PageStripContainerView(frame: CGRect(x: 40, y: 30, width: 1500, height: 800))
        let strip = NSView(frame: CGRect(x: 0, y: 0, width: 4500, height: 800))
        parent.addSubview(container)
        container.addSubview(strip)
        container.setStripX(1500)
        container.excludedRects = [
            CGRect(x: 0, y: 0, width: 1500, height: 100),
            CGRect(x: 0, y: 768, width: 1500, height: 32)
        ]

        XCTAssertNil(container.hitTest(CGPoint(x: 50, y: 50)))
        XCTAssertNil(container.hitTest(CGPoint(x: 50, y: 810)))
        XCTAssertTrue(container.hitTest(CGPoint(x: 50, y: 140)) === strip)
        container.hitTestingEnabled = false
        XCTAssertNil(container.hitTest(CGPoint(x: 50, y: 140)))
    }

    @MainActor func testHitTestingWithUnflippedParent() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let container = PageStripContainerView(frame: CGRect(x: 40, y: 30, width: 1500, height: 800))
        let entry = NSView(frame: CGRect(x: 1500, y: 100, width: 30, height: 30))
        parent.addSubview(container)
        container.addSubview(entry)
        container.setStripX(1500)
        XCTAssertTrue(container.hitTest(CGPoint(x: 50, y: 720)) === entry)
        container.excludedRects = [CGRect(x: 0, y: 0, width: 1500, height: 100)]
        XCTAssertNil(container.hitTest(CGPoint(x: 50, y: 800)))
    }

    @MainActor func testPointAndRectConversionsFollowDisplayedGeometry() {
        let pager = PagerController()
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        pager.attach(container)
        defer { pager.detach(container) }
        pager.configure(pageWidth: 1500, pageCount: 3)
        pager.jump(to: 1)
        for point in [CGPoint(x: 10, y: 42), CGPoint(x: -12, y: -3), CGPoint(x: 1600, y: 800)] {
            XCTAssertEqual(pager.stripPoint(fromViewport: point), CGPoint(x: point.x + 1500, y: point.y))
            XCTAssertEqual(pager.viewportPoint(fromStrip: pager.stripPoint(fromViewport: point)), point)
        }
        XCTAssertEqual(pager.viewportRect(fromStrip: CGRect(x: 1510, y: 20, width: 90, height: 100)),
                       CGRect(x: 10, y: 20, width: 90, height: 100))
        XCTAssertEqual(container.bounds.origin.x, 1500)
    }

    @MainActor func testDirectEventsWriteImmediatelyWithoutPublishingPageState() {
        let pager = PagerController()
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        pager.attach(container)
        defer { pager.detach(container) }
        pager.configure(pageWidth: 1500, pageCount: 3)
        pager.jump(to: 1)
        let changes = ObservationCount()
        withObservationTracking {
            _ = pager.state.targetPage
            _ = pager.state.restingPage
        } onChange: {
            changes.value += 1
        }

        pager.handleScroll(dx: 2, dy: 1, phase: .began, time: 10)
        XCTAssertEqual(container.bounds.origin.x, 1500)
        pager.handleScroll(dx: 2, dy: 1, phase: .changed, time: 10.01)
        XCTAssertEqual(container.bounds.origin.x, 1496)
        for i in 1...20 {
            pager.handleScroll(dx: -5, dy: 0, phase: .changed, time: 10.01 + Double(i) * 0.01)
        }
        XCTAssertEqual(container.bounds.origin.x, 1596)
        pager.advanceFrame(timestamp: 10.22, targetTimestamp: 10.23, now: 10.22)
        if ProcessInfo.processInfo.environment["LAUNCHPADPRO_SWIPE_PREDICT"] != "1" {
            XCTAssertEqual(container.bounds.origin.x, 1596)
        }
        XCTAssertEqual(changes.value, 0)
        pager.handleScroll(dx: -5, dy: 0, phase: .ended, time: 10.23)
        XCTAssertEqual(pager.state.targetPage, 2)
        XCTAssertEqual(pager.state.restingPage, 1)
        if FrameMeter.enabled {
            XCTAssertEqual(FrameMeter.stats?.sumRaw, -101)
            XCTAssertEqual(FrameMeter.stats?.sumApplied, -101)
            XCTAssertEqual(FrameMeter.stats?.eventTimes.count, 23)
        }
        pager.advanceFrame(timestamp: 11.22, targetTimestamp: 11.23, now: 11.22)
        XCTAssertEqual(container.bounds.origin.x, 3000)
        XCTAssertEqual(pager.state.restingPage, 2)
        XCTAssertEqual(changes.value, 1)
        XCTAssertNil(FrameMeter.stats)
    }

    @MainActor func testNSEventMappingAndMomentumRejection() throws {
        let pager = PagerController()
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        pager.attach(container)
        defer { pager.detach(container) }
        pager.configure(pageWidth: 1500, pageCount: 3)
        pager.jump(to: 1)

        func event(dx: Int32, phase: CGScrollPhase?, momentum: CGMomentumScrollPhase = .none) throws -> NSEvent {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                          wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
            return try XCTUnwrap(NSEvent(cgEvent: cg))
        }

        let began = try event(dx: -10, phase: .began)
        pager.handleScroll(began)
        XCTAssertEqual(container.bounds.origin.x, 1500 - began.scrollingDeltaX)
        let beforeMomentum = container.bounds.origin.x
        let momentum = try event(dx: -100, phase: nil, momentum: .begin)
        XCTAssertTrue(momentum.phase.isEmpty)
        XCTAssertFalse(momentum.momentumPhase.isEmpty)
        pager.handleScroll(momentum)
        XCTAssertEqual(container.bounds.origin.x, beforeMomentum)
        pager.handleScroll(try event(dx: 0, phase: .cancelled))
        let now = CACurrentMediaTime()
        pager.advanceFrame(timestamp: now + 1, targetTimestamp: now + 1.01, now: now + 1)
        XCTAssertEqual(container.bounds.origin.x, 1500)
        XCTAssertEqual(pager.state.restingPage, 1)
    }

    @MainActor func testLifecycleConfigureAndCommands() {
        let pager = PagerController()
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        pager.configure(pageWidth: 1500, pageCount: 4)
        pager.jump(to: 2)
        XCTAssertEqual(pager.state.targetPage, 0)
        pager.attach(container)
        pager.configure(pageWidth: 1500, pageCount: 4)
        pager.jump(to: 3)
        pager.configure(pageWidth: 1200, pageCount: 2)
        XCTAssertEqual(container.bounds.origin.x, 1200)
        XCTAssertEqual(pager.state.targetPage, 1)
        pager.isLocked = true
        pager.handleScroll(dx: 100, dy: 0, phase: .began, time: 10)
        XCTAssertEqual(container.bounds.origin.x, 1200)
        pager.step(by: -1)
        XCTAssertEqual(pager.state.targetPage, 0)
        pager.stop()
        XCTAssertEqual(container.bounds.origin.x, 0)
        pager.jump(to: 1)
        pager.reset()
        XCTAssertEqual(container.bounds.origin.x, 0)
        pager.jump(to: 1)
        pager.detach(container)
        pager.jump(to: 0)
        XCTAssertEqual(pager.state.targetPage, 1)
        pager.attach(container)
        XCTAssertEqual(container.bounds.origin.x, 0)
        XCTAssertFalse(pager.isLocked)
        pager.detach(container)
    }
}

private struct LayoutAnimationProbe: View {
    let signature: PageStripLayoutSignature
    let transaction: Transaction
    let position: CGFloat
    var bridgeEnabled = true
    var record: (Transaction) -> Void

    var body: some View {
        let entry = Color.clear
            .frame(width: 20, height: 20)
            .position(x: position, y: 20)
            .transaction { record($0) }
        if bridgeEnabled {
            entry.modifier(PageStripLayoutAnimation(signature: signature, transaction: transaction))
        } else {
            entry
        }
    }
}

@MainActor
private final class FlippedTestView: NSView {
    override var isFlipped: Bool { true }
}

private final class ObservationCount: @unchecked Sendable {
    var value = 0
}
