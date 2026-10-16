import AppKit
import QuartzCore
import SwiftUI

struct PageStripReorder {
    private var generation: UInt64 = 0
    private var tokens: [String: UInt64] = [:]

    func token(for id: String) -> UInt64 { tokens[id, default: 0] }

    // Called only by drag preview/commit/merge, never by paging or view evaluation.
    mutating func record(from old: [[LaunchEntry]], to new: [[LaunchEntry]], releasedID: String? = nil) {
        let before = PageStripReordering.locations(in: old)
        let after = PageStripReordering.locations(in: new)
        generation &+= 1
        for (id, location) in after {
            if let previous = before[id], previous != location || id == releasedID {
                tokens[id] = generation
            }
        }
    }
}

struct PageStripReorderAnimation: ViewModifier {
    static let flow = Animation.spring(response: 0.24, dampingFraction: 0.80)
    let reorderToken: UInt64
    var animationsDisabled = false

    func body(content: Content) -> some View {
        content
            .animation(animationsDisabled ? nil : Self.flow, value: reorderToken)
            // Page-window changes and folder transactions cannot animate grid positions.
            .transaction { $0.animation = nil }
    }
}

struct PageStripEntryPlacement: ViewModifier {
    let position: CGPoint
    let reorderToken: UInt64
    var isDragging = false
    var animationsDisabled = false

    func body(content: Content) -> some View {
        content
            // Keep the gesture owner mounted, but hide its icon AND label immediately.
            .opacity(isDragging ? 0 : 1)
            .transaction { $0.animation = nil }
            .position(position)
            .modifier(PageStripReorderAnimation(
                reorderToken: reorderToken, animationsDisabled: animationsDisabled || isDragging
            ))
            .transition(.identity)
    }
}

enum PageStripWindow {
    static func entries(
        from entries: [PlacedEntry],
        activeLocations: [String: (page: Int, index: Int)],
        restingPage: Int,
        draggingID: String?
    ) -> [PlacedEntry] {
        let pages = (restingPage - 2)...(restingPage + 2)
        return entries.filter { placed in
            if placed.id == draggingID || pages.contains(placed.page) { return true }
            guard let active = activeLocations[placed.id] else { return false }
            return pages.contains(active.page)
        }
    }
}

@MainActor
final class PageStripContainerView: NSView {
    var hitTestingEnabled = true
    var excludedRects: [CGRect] = []
    private(set) var hostingView: StripHostingView?

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {}

    func install(content: PageStripContent, size: CGSize) {
        let host = StripHostingView(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = CGRect(origin: .zero, size: size)
        addSubview(host)
        hostingView = host
    }

    func setStripX(_ x: CGFloat) {
        guard bounds.origin.x != x else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setBoundsOrigin(CGPoint(x: x, y: 0))
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestingEnabled else { return nil }
        let local = convert(point, from: superview)
        let viewport = CGPoint(x: local.x - bounds.origin.x, y: local.y - bounds.origin.y)
        guard CGRect(origin: .zero, size: bounds.size).contains(viewport),
              !excludedRects.contains(where: { $0.contains(viewport) }) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class StripHostingView: NSHostingView<PageStripContent> {
    override var acceptsFirstResponder: Bool { false }
}

struct PageStripRepresentable: NSViewRepresentable {
    let pager: PagerController
    let size: CGSize
    let pageCount: Int
    let hitTestingEnabled: Bool
    let excludedRects: [CGRect]
    var content: PageStripContent

    func makeCoordinator() -> PagerController { pager }

    func makeNSView(context: Context) -> PageStripContainerView {
        let view = PageStripContainerView(frame: CGRect(origin: .zero, size: size))
        var root = content
        root.dimAnimated = !context.transaction.disablesAnimations
        root.reorderAnimationsDisabled = context.transaction.disablesAnimations
        view.install(content: root, size: stripSize)
        view.hitTestingEnabled = hitTestingEnabled
        view.excludedRects = excludedRects
        pager.attach(view)
        return view
    }

    func updateNSView(_ view: PageStripContainerView, context: Context) {
        view.hostingView?.frame = CGRect(origin: .zero, size: stripSize)
        view.hitTestingEnabled = hitTestingEnabled
        view.excludedRects = excludedRects
        var root = content
        root.dimAnimated = !context.transaction.disablesAnimations
        root.reorderAnimationsDisabled = context.transaction.disablesAnimations
        withTransaction(context.transaction) {
            view.hostingView?.rootView = root
        }
    }

    static func dismantleNSView(_ view: PageStripContainerView, coordinator: PagerController) {
        coordinator.detach(view)
    }

    private var stripSize: CGSize {
        CGSize(width: CGFloat(max(1, pageCount)) * size.width, height: size.height)
    }
}

struct PageStripContent: View {
    @ObservedObject var model: LaunchModel
    let entries: [PlacedEntry]
    let positions: [String: CGPoint]
    let reorder: PageStripReorder
    let size: CGSize
    let cell: CGSize
    let draggingID: String?
    let folderTargetID: String?
    let dragEnabled: Bool
    let folderProgress: CGFloat
    var dimAnimated = true
    var reorderAnimationsDisabled = false
    var onLaunch: (String) -> Void
    var onDismiss: () -> Void
    var onDragChanged: (LaunchEntry, CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    var body: some View {
        let _ = FrameMeter.noteBody(.strip)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            ForEach(entries) { placed in
                LauncherEntryView(
                    model: model,
                    entry: placed.entry,
                    cell: cell,
                    isDragging: placed.id == draggingID,
                    isFolderTarget: placed.id == folderTargetID,
                    onLaunch: onLaunch
                )
                .equatable()
                .highPriorityGesture(dragGesture(placed.entry), including: dragEnabled ? .all : .none)
                .frame(width: cell.width, height: cell.height)
                .modifier(PageStripEntryPlacement(
                    position: positions[placed.id] ?? .zero,
                    reorderToken: reorder.token(for: placed.id),
                    isDragging: placed.id == draggingID,
                    animationsDisabled: reorderAnimationsDisabled
                ))
                .zIndex(1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "page-strip")
        .blur(radius: 18 * folderProgress)
        .saturation(Double(1 - 0.28 * folderProgress))
        .brightness(Double(-0.16 * folderProgress))
        .opacity(Double(1 - 0.58 * folderProgress))
        .animation(dimAnimated ? .easeInOut(duration: 0.20) : nil, value: folderProgress)
        .ignoresSafeArea()
    }

    private func dragGesture(_ entry: LaunchEntry) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("page-strip"))
            .onChanged { onDragChanged(entry, $0.location) }
            .onEnded { onDragEnded($0.location) }
    }
}

struct PageDotsView: View {
    let state: PagerState
    let pageCount: Int
    let navigablePageCount: Int
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<navigablePageCount, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == state.targetPage ? 0.94 : (index >= pageCount ? 0.18 : 0.36)))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(index) }
            }
        }
    }
}
