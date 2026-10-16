import AppKit
import Observation
import QuartzCore
import SwiftUI
import XCTest
@testable import LaunchpadProCodex

final class PageStripViewTests: XCTestCase {
    func testPreviewMovesOnlyContiguousRangeOnSamePage() {
        let pages: [[LaunchEntry]] = (0..<3).map { page in
            (0..<8).map { .app("\(page)-\($0)") }
        }
        let before = PageStripReordering.locations(in: pages)
        for page in pages.indices {
            for source in 0..<8 {
                for target in 0..<8 {
                    let id = pages[page][source].id
                    let preview = PageStripReordering.preview(
                        pages: pages, draggingID: id, target: (page, target), perPage: 8
                    )
                    let after = PageStripReordering.locations(in: preview)
                    var reorder = PageStripReorder()
                    reorder.record(from: pages, to: preview)
                    for (entryID, location) in before {
                        let affected = source != target && location.page == page
                            && (min(source, target)...max(source, target)).contains(location.index)
                        XCTAssertEqual(after[entryID] != location, affected, "\(page):\(source)→\(target) \(entryID)")
                        XCTAssertEqual(reorder.token(for: entryID) != 0, affected)
                    }
                    XCTAssertEqual(preview[page][target].id, id)
                    XCTAssertEqual(preview.flatMap { $0 }.count, 24)
                }
            }
        }
    }

    func testCrossPagePreviewMatchesOriginalOverflowWithoutRecascading() {
        let pages: [[LaunchEntry]] = [
            ["a", "b", "c", "d"], ["e", "f", "g", "h"], ["i", "j"], ["k", "l"]
        ].map { $0.map(LaunchEntry.app) }
        let preview = PageStripReordering.preview(pages: pages, draggingID: "app:b", target: (1, 1), perPage: 4)
        XCTAssertEqual(preview, [["a", "c", "d"], ["e", "b", "f", "g"], ["h", "i", "j"], ["k", "l"]]
            .map { $0.map(LaunchEntry.app) })
        // Every pointer target is computed from the original pages, not the previous preview.
        let returned = PageStripReordering.preview(pages: pages, draggingID: "app:b", target: (0, 1), perPage: 4)
        XCTAssertEqual(returned, pages)
        let emptyPage = PageStripReordering.preview(pages: pages, draggingID: "app:b", target: (4, 20), perPage: 4)
        XCTAssertEqual(emptyPage[4], [.app("b")])
        XCTAssertEqual(Array(emptyPage[1...3]), Array(pages[1...3]))
        XCTAssertEqual(PageStripReordering.preview(pages: pages, draggingID: "missing", target: (1, 0), perPage: 4), pages)
    }

    func testReorderTokensTrackOnlyMovedEntriesReleaseAndMerge() {
        let original: [[LaunchEntry]] = [[.app("a"), .app("b"), .app("c"), .app("d")]]
        let preview: [[LaunchEntry]] = [[.app("b"), .app("a"), .app("c"), .app("d")]]
        var reorder = PageStripReorder()
        reorder.record(from: original, to: preview)
        let a = reorder.token(for: "app:a")
        let b = reorder.token(for: "app:b")
        XCTAssertGreaterThan(a, 0)
        XCTAssertGreaterThan(b, 0)
        XCTAssertEqual(reorder.token(for: "app:c"), 0)
        reorder.record(from: preview, to: preview, releasedID: "app:a")
        XCTAssertGreaterThan(reorder.token(for: "app:a"), a)
        XCTAssertEqual(reorder.token(for: "app:b"), b)
        let merged: [[LaunchEntry]] = [[.folder(FolderRecord(id: "f", name: "Tools", appIDs: ["a", "b"])), .app("c"), .app("d")]]
        reorder.record(from: preview, to: merged)
        XCTAssertGreaterThan(reorder.token(for: "app:c"), 0)
        XCTAssertGreaterThan(reorder.token(for: "app:d"), 0)
        XCTAssertEqual(reorder.token(for: "folder:f"), 0, "New identities must appear without sliding in")
        let token = reorder.token(for: "app:c")
        let renamed: [[LaunchEntry]] = [[.folder(FolderRecord(id: "f", name: "Renamed", appIDs: ["b", "a"])), .app("c"), .app("d")]]
        reorder.record(from: merged, to: renamed)
        XCTAssertEqual(reorder.token(for: "app:c"), token)
        XCTAssertEqual(reorder.token(for: "folder:f"), 0)
    }

    @MainActor func testEquatableIncludesEntryMetadataAndEveryVisualInput() {
        let cell = CGSize(width: 100, height: 120)
        func input(_ entry: LaunchEntry, cell: CGSize = CGSize(width: 100, height: 120),
                   dragging: Bool = false, target: Bool = false) -> LauncherEntryView.RenderInput {
            .init(entry: entry, cell: cell, isDragging: dragging, isFolderTarget: target)
        }
        XCTAssertEqual(input(.app("a")), input(.app("a")))
        XCTAssertNotEqual(input(.app("a")), input(.app("b")))
        XCTAssertNotEqual(input(.app("a")), input(.app("a"), cell: CGSize(width: cell.width + 1, height: cell.height)))
        XCTAssertNotEqual(input(.app("a")), input(.app("a"), dragging: true))
        XCTAssertNotEqual(input(.app("a")), input(.app("a"), target: true))
        let folder = FolderRecord(id: "f", name: "Original", appIDs: ["a", "b"])
        for changed in [FolderRecord(id: "f", name: "Renamed", appIDs: ["a", "b"]),
                        FolderRecord(id: "f", name: "Original", appIDs: ["b", "a"]),
                        FolderRecord(id: "f", name: "Original", appIDs: ["a", "b", "c"])] {
            XCTAssertNotEqual(input(.folder(folder)), input(.folder(changed)))
        }
    }

    @MainActor func testCoalescedDragPointUpdateKeepsReorderAnimation() {
        var observed: [Animation?] = []
        func probe(_ token: UInt64, _ position: CGFloat) -> LayoutAnimationProbe {
            LayoutAnimationProbe(token: token, position: position, record: { observed.append($0.animation) })
        }
        let host = NSHostingView(rootView: probe(0, 20))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(observed.allSatisfy { $0 == nil })
        observed.removeAll()
        withAnimation(PageStripReorderAnimation.flow) { host.rootView = probe(1, 100) }
        // The next pointer update has no outer animation and arrives before layout.
        host.rootView = probe(1, 100)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(observed.contains { $0 == PageStripReorderAnimation.flow })
        for token in UInt64(2)...4 { // Release, merge, then another preview.
            observed.removeAll()
            host.rootView = probe(token, CGFloat(token) * 60)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(observed.contains { $0 == PageStripReorderAnimation.flow })
        }
    }

    @MainActor func testUnchangedTokenAndDisabledAnimationsStayImmediate() {
        for disabled in [false, true] {
            var observed: [Animation?] = []
            let host = NSHostingView(rootView: LayoutAnimationProbe(token: 0, position: 20,
                record: { observed.append($0.animation) }))
            host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
            host.layoutSubtreeIfNeeded()
            observed.removeAll()
            host.rootView = LayoutAnimationProbe(token: disabled ? 1 : 0, position: 100,
                disabled: disabled, inheritedAnimation: .linear(duration: 1),
                record: { observed.append($0.animation) })
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(observed.isEmpty)
            XCTAssertTrue(observed.allSatisfy { $0 == nil })
        }
    }

    @MainActor func testWindowChangesDoNotAnimateEvenWithPriorReorderTokens() {
        let pages: [[LaunchEntry]] = (0..<8).map { [.app("\($0)")] }
        let entries = pages.enumerated().map { PlacedEntry(page: $0.offset, index: 0, entry: $0.element[0]) }
        var observed: [Animation?] = []
        func probe(_ page: Int) -> WindowAnimationProbe {
            WindowAnimationProbe(entries: PageStripWindow.entries(from: entries, activeLocations: [:],
                restingPage: page, draggingID: nil), record: { observed.append($0.animation) })
        }
        let host = NSHostingView(rootView: probe(0))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
        host.layoutSubtreeIfNeeded()
        for page in [1, 3, 7, 0] {
            observed.removeAll()
            withAnimation(.linear(duration: 1)) { host.rootView = probe(page) }
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(observed.allSatisfy { $0 == nil }, "Window update must not replay reorder animation")
        }
    }

    @MainActor func testDraggedStripEntryHasNoVisibleIconOrLabel() throws {
        func rendered(hidden: Bool, x: CGFloat) throws -> NSBitmapImageRep {
            let view = ZStack(alignment: .topLeading) {
                Color.white
                VStack(spacing: 4) {
                    Color(red: 1, green: 0, blue: 0).frame(width: 24, height: 24)
                    Color(red: 0, green: 0, blue: 1).frame(width: 40, height: 8)
                }
                .frame(width: 50, height: 50)
                .modifier(PageStripEntryPlacement(position: CGPoint(x: x, y: 40),
                    reorderToken: 1, isDragging: hidden))
            }.frame(width: 140, height: 80)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        }
        func coloredBounds(_ bitmap: NSBitmapImageRep, red: Bool) -> CGRect? {
            var points: [CGPoint] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.greenComponent < 0.3 && (red ? color.redComponent : color.blueComponent) > 0.7 {
                        points.append(CGPoint(x: x, y: y))
                    }
                }
            }
            guard let first = points.first else { return nil }
            return points.dropFirst().reduce(CGRect(origin: first, size: CGSize(width: 1, height: 1))) {
                $0.union(CGRect(origin: $1, size: CGSize(width: 1, height: 1)))
            }
        }
        let visible = try rendered(hidden: false, x: 35)
        let dragged = try rendered(hidden: true, x: 35)
        let moved = try rendered(hidden: false, x: 95)
        for red in [true, false] {
            let originalBounds = try XCTUnwrap(coloredBounds(visible, red: red))
            XCTAssertNil(coloredBounds(dragged, red: red))
            let movedBounds = try XCTUnwrap(coloredBounds(moved, red: red))
            XCTAssertEqual(movedBounds.minX - originalBounds.minX, 60)
            XCTAssertEqual(movedBounds.minY, originalBounds.minY)
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

    @MainActor func testPagingHostingBodiesStayIdleDuringTrackingAndSnap() throws {
        // Real controller/container and nested hosting trees, without LaunchModel's disk writes.
        for direction in [-1, 1] {
            let pager = PagerController()
            let counts = PagingBodyCounts()
            let host = NSHostingView(rootView: PagingBodyProbe(pager: pager, counts: counts))
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: 1500, height: 800)
            func flush() {
                host.layoutSubtreeIfNeeded()
                counts.stripHost?.layoutSubtreeIfNeeded()
            }
            flush()
            let container = try XCTUnwrap(counts.container)
            defer { pager.detach(container) }
            pager.configure(pageWidth: 1500, pageCount: 8)
            pager.jump(to: 3)
            flush()
            XCTAssertGreaterThan(counts.paged, 0)
            XCTAssertGreaterThan(counts.strip, 0)
            let initial = [counts.paged, counts.strip]
            pager.handleScroll(dx: 0, dy: 0, phase: .began, time: 10)
            for event in 1...30 {
                let time = 10 + Double(event) / 120
                pager.handleScroll(dx: CGFloat(-direction * 12), dy: 0, phase: .changed, time: time)
                pager.advanceFrame(timestamp: time, targetTimestamp: time + 1 / 120, now: time)
                flush()
                XCTAssertEqual([counts.paged, counts.strip], initial)
                if FrameMeter.enabled { XCTAssertEqual(FrameMeter.stats?.bodies, [0, 0, 0]) }
            }
            XCTAssertEqual(container.bounds.origin.x, CGFloat(4500 + direction * 360), accuracy: 1e-6)
            pager.handleScroll(dx: 0, dy: 0, phase: .ended, time: 10.25)
            XCTAssertEqual(pager.state.targetPage, 3 + direction)
            var snapFrames = 0
            for frame in 1...120 {
                let time = 10.25 + Double(frame) / 120
                if FrameMeter.enabled { XCTAssertEqual(FrameMeter.stats?.bodies, [0, 0, 0]) }
                pager.advanceFrame(timestamp: time, targetTimestamp: time + 1 / 120, now: time)
                if pager.state.restingPage != 3 { break }
                snapFrames += 1
                flush()
                XCTAssertEqual([counts.paged, counts.strip], initial)
                if FrameMeter.enabled { XCTAssertEqual(FrameMeter.stats?.bodies, [0, 0, 0]) }
            }
            XCTAssertGreaterThan(snapFrames, 20)
            XCTAssertEqual(pager.state.restingPage, 3 + direction)
            XCTAssertEqual(container.bounds.origin.x, CGFloat(3 + direction) * 1500)
            XCTAssertNil(FrameMeter.stats, "Session must end before the resting-page update")
            flush()
            XCTAssertGreaterThan(counts.paged, initial[0], "Positive control: settlement must update the window")
            XCTAssertGreaterThan(counts.strip, initial[1])
        }
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
    let token: UInt64
    let position: CGFloat
    var disabled = false
    var inheritedAnimation: Animation?
    var record: (Transaction) -> Void

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .position(x: position, y: 20)
            .transaction { record($0) }
            .modifier(PageStripReorderAnimation(reorderToken: token, animationsDisabled: disabled))
            .transaction { $0.animation = inheritedAnimation }
    }
}

private struct WindowAnimationProbe: View {
    let entries: [PlacedEntry]
    var record: (Transaction) -> Void

    var body: some View {
        ZStack {
            ForEach(entries) { entry in
                Color.clear
                    .frame(width: 20, height: 20)
                    .position(x: CGFloat(entry.page * 40), y: 20)
                    .transaction { record($0) }
                    .modifier(PageStripReorderAnimation(reorderToken: 42))
                    .transition(.identity)
            }
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

@MainActor
private final class PagingBodyCounts {
    var paged = 0
    var strip = 0
    weak var container: PageStripContainerView?
    weak var stripHost: NSHostingView<PagingStripProbe>?
}

private struct PagingBodyProbe: View {
    let pager: PagerController
    let counts: PagingBodyCounts

    var body: some View {
        let _ = FrameMeter.noteBody(.paged)
        let _ = { counts.paged += 1 }()
        let entries = (0..<8).map { PlacedEntry(page: $0, index: 0, entry: .app("\($0)")) }
        let window = PageStripWindow.entries(from: entries, activeLocations: [:],
                                             restingPage: pager.state.restingPage, draggingID: nil)
        ZStack {
            PagingStripRepresentable(pager: pager, entries: window, counts: counts)
            PageDotsView(state: pager.state, pageCount: 8, navigablePageCount: 8, onSelect: { _ in })
        }
        .frame(width: 1500, height: 800)
    }
}

private struct PagingStripRepresentable: NSViewRepresentable {
    let pager: PagerController
    let entries: [PlacedEntry]
    let counts: PagingBodyCounts

    func makeNSView(context: Context) -> PageStripContainerView {
        let container = PageStripContainerView(frame: CGRect(x: 0, y: 0, width: 1500, height: 800))
        let host = NSHostingView(rootView: PagingStripProbe(entries: entries, counts: counts))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = CGRect(x: 0, y: 0, width: 12000, height: 800)
        container.addSubview(host)
        counts.container = container
        counts.stripHost = host
        pager.attach(container)
        return container
    }

    func updateNSView(_ view: PageStripContainerView, context: Context) {
        counts.stripHost?.rootView = PagingStripProbe(entries: entries, counts: counts)
    }
}

private struct PagingStripProbe: View {
    let entries: [PlacedEntry]
    let counts: PagingBodyCounts

    var body: some View {
        let _ = FrameMeter.noteBody(.strip)
        let _ = { counts.strip += 1 }()
        ZStack(alignment: .topLeading) {
            ForEach(entries) { entry in
                VStack {
                    Color.red.frame(width: 50, height: 50)
                    Text(entry.id)
                }
                .frame(width: 100, height: 100)
                .modifier(PageStripEntryPlacement(position: CGPoint(x: CGFloat(entry.page * 1500 + 100), y: 100),
                                                   reorderToken: 42))
            }
        }
        .frame(width: 12000, height: 800, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
