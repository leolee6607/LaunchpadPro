import AppKit
import QuartzCore
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private let model: LaunchModel
    private var panel: OverlayPanel?
    private var localMonitor: Any?
    private var wheelAccumulation: CGFloat = 0
    private var lastWheelPageFlip = Date.distantPast
    private let pager = PagerController()

    var onOpenSettings: () -> Void = {}
    var onRescan: () -> Void = {}
    var onQuit: () -> Void = {}

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: LaunchModel) {
        self.model = model
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let screen = screenUnderMouse() else { return }

        model.reload()
        model.searchText = ""
        model.openFolderID = nil
        LauncherBus.shared.targetScreenTopSafeArea = screen.safeAreaInsets.top
        LauncherBus.shared.reset()
        pager.reset()

        let panel = panel ?? makePanel(screen: screen)
        self.panel = panel

        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installLocalMonitor()
    }

    func hide() {
        guard let panel else { return }
        removeLocalMonitor()
        pager.stop()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func makePanel(screen: NSScreen) -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = panel.contentView?.bounds ?? NSScreen.main?.frame ?? .zero
        effect.autoresizingMask = [.width, .height]

        let root = LauncherRootView(
            model: model,
            pager: pager,
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.onOpenSettings()
            },
            onRescan: { [weak self] in self?.onRescan() },
            onQuit: { [weak self] in self?.onQuit() }
        )
        let host = NSHostingView(rootView: root)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        panel.contentView = effect
        return panel
    }

    private func screenUnderMouse() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        let fallbackIndex = NSScreen.main.flatMap { mainScreen in
            screens.firstIndex { $0 === mainScreen }
        }
        guard let index = Self.targetScreenIndex(
            mouseLocation: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame),
            fallbackIndex: fallbackIndex
        ) else {
            return nil
        }
        return screens[index]
    }

    nonisolated static func targetScreenIndex(
        mouseLocation: CGPoint,
        screenFrames: [CGRect],
        fallbackIndex: Int?
    ) -> Int? {
        if let hoveredIndex = screenFrames.firstIndex(where: { $0.contains(mouseLocation) }) {
            return hoveredIndex
        }
        if let fallbackIndex, screenFrames.indices.contains(fallbackIndex) {
            return fallbackIndex
        }
        return screenFrames.indices.first
    }

    private func installLocalMonitor() {
        removeLocalMonitor()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }

            if event.type == .scrollWheel {
                self.handleScroll(event)
                return event
            }

            if event.keyCode == 53 {
                if self.model.openFolderID != nil {
                    self.model.openFolderID = nil
                    return nil
                }
                self.hide()
                return nil
            }

            return event
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard model.openFolderID == nil, !model.settings.verticalScroll else { return }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if !event.phase.isEmpty || !event.momentumPhase.isEmpty {
            pager.handleScroll(event)
            return
        }

        guard abs(dx) > abs(dy) else {
            wheelAccumulation = 0
            return
        }

        wheelAccumulation += dx
        guard Date().timeIntervalSince(lastWheelPageFlip) > 0.3 else { return }

        if wheelAccumulation <= -40 {
            pager.step(by: 1)
            wheelAccumulation = 0
            lastWheelPageFlip = Date()
        } else if wheelAccumulation >= 40 {
            pager.step(by: -1)
            wheelAccumulation = 0
            lastWheelPageFlip = Date()
        }
    }
}
