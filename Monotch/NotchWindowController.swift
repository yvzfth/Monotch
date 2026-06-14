import Cocoa
import SwiftUI
import Combine

private final class NotchPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchWindowController {
    static let shared = NotchWindowController()

    private var window: NSWindow?
    private let ui = NotchUIState.shared
    private var cancellables: Set<AnyCancellable> = []
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingCollapse: DispatchWorkItem?
    private var expandedPointerWatchdog: Timer?

    private let expandedWidth: CGFloat = 440
    private let collapsedSize = CGSize(width: 184, height: 24)
    private let topOverlap: CGFloat = 10

    private init() {
        createWindowIfNeeded()
        startHoverMonitoring()
        ui.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.animateSizeChange(expanded: expanded)
                if expanded {
                    self?.startExpandedPointerWatchdog()
                } else {
                    self?.stopExpandedPointerWatchdog()
                }
            }
            .store(in: &cancellables)

        ui.$expandedHeight
            .removeDuplicates()
            .sink { [weak self] _ in
                guard self?.ui.isExpanded == true else { return }
                self?.animateSizeChange(expanded: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.scheduleCollapseIfPointerOutside(after: 0.05)
            }
            .store(in: &cancellables)
    }

    deinit {
        stopExpandedPointerWatchdog()
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    func toggle() {
        guard let window else {
            createWindowIfNeeded()
            if let win = self.window {
                showWithAnimation(win)
            }
            return
        }

        if window.isVisible {
            hideWithAnimation(window)
        } else {
            positionWindow()
            showWithAnimation(window)
        }
    }

    func hideCompletely() {
        ui.isExpanded = false
        window?.orderOut(nil)
    }

    func showCollapsed() {
        createWindowIfNeeded()
        ui.isExpanded = false
        if let win = window {
            positionWindow()
            win.alphaValue = 1
            win.orderFrontRegardless()
        }
    }

    func showExpanded() {
        createWindowIfNeeded()
        ui.isExpanded = true
        if let win = window {
            positionWindow()
            win.alphaValue = 1
            win.orderFrontRegardless()
            startExpandedPointerWatchdog()
        }
    }

    func pointerEnteredNotch() {
        pendingCollapse?.cancel()
        let openOnHover = UserDefaults.standard.object(forKey: MonotchSettingsKey.openOnHover) as? Bool ?? true
        guard openOnHover, ui.isExpanded == false else { return }
        ui.isExpanded = true
    }

    func pointerLeftNotch() {
        scheduleCollapseIfPointerOutside(after: 0.12)
    }

    private func showWithAnimation(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func hideWithAnimation(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }

    private func createWindowIfNeeded() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let notchWidth: CGFloat = collapsedSize.width
        let notchHeight: CGFloat = collapsedSize.height

        let screenFrame = screen.frame
        let originX = screenFrame.midX - notchWidth / 2
        let originY = screenFrame.maxY - notchHeight + topOverlap

        let window = NotchPanelWindow(
            contentRect: NSRect(x: originX, y: originY, width: notchWidth, height: notchHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false

        let content = NotchIslandContainerView()
        let hosting = NSHostingView(rootView: content)
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.makeFirstResponder(hosting)

        self.window = window
    }

    private func startHoverMonitoring() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handlePointerMoved()
            return event
        }
    }

    private func handlePointerMoved() {
        guard window?.isVisible == true else { return }
        guard ui.isInteractionHeld == false else { return }

        if isPointerInsideNotch() {
            pointerEnteredNotch()
        } else if ui.isExpanded {
            pointerLeftNotch()
        }
    }

    private func scheduleCollapseIfPointerOutside(after delay: TimeInterval) {
        pendingCollapse?.cancel()
        guard ui.isExpanded else { return }
        guard ui.isInteractionHeld == false else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.ui.isExpanded else { return }
            guard self.ui.isInteractionHeld == false else { return }

            if self.isPointerInsideNotch() == false {
                self.ui.isExpanded = false
            }
        }

        pendingCollapse = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startExpandedPointerWatchdog() {
        expandedPointerWatchdog?.invalidate()

        let timer = Timer(timeInterval: 0.28, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.window?.isVisible == true else { return }
                guard self.ui.isExpanded else { return }
                guard self.ui.isInteractionHeld == false else { return }

                if self.isPointerInsideNotch() == false {
                    self.scheduleCollapseIfPointerOutside(after: 0)
                }
            }
        }

        expandedPointerWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)

        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePointerMoved()
                }
            }
        }
    }

    private func stopExpandedPointerWatchdog() {
        expandedPointerWatchdog?.invalidate()
        expandedPointerWatchdog = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        pendingCollapse?.cancel()
    }

    private func isPointerInsideNotch() -> Bool {
        guard let window else { return false }

        let point = NSEvent.mouseLocation
        let hitFrame = window.frame.insetBy(dx: ui.isExpanded ? -2 : -8, dy: ui.isExpanded ? -2 : -6)
        return hitFrame.contains(point)
    }

    private func positionWindow() {
        guard let window else { return }

        let screenFrame = screenFrame(for: window)
        let target = ui.isExpanded ? expandedSize : collapsedSize
        let notchWidth = target.width
        let notchHeight = target.height

        let originX = screenFrame.midX - notchWidth / 2
        let originY = screenFrame.maxY - notchHeight + topOverlap

        window.setFrame(
            NSRect(x: originX, y: originY, width: notchWidth, height: notchHeight),
            display: true
        )
    }

    private func animateSizeChange(expanded: Bool) {
        guard let window else { return }
        guard window.isVisible else { return }

        let newFrame = targetFrame(expanded: expanded, for: window)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = expanded ? 0.14 : 0.11
            context.timingFunction = CAMediaTimingFunction(name: expanded ? .easeOut : .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.window?.setFrame(newFrame, display: true)
        })
    }

    private func targetFrame(expanded: Bool, for window: NSWindow) -> NSRect {
        let target = expanded ? expandedSize : collapsedSize
        let screenFrame = screenFrame(for: window)

        let centerX: CGFloat
        let topY: CGFloat
        if expanded {
            centerX = screenFrame.midX
            topY = screenFrame.maxY + topOverlap
        } else {
            centerX = window.frame.midX
            topY = window.frame.maxY
        }

        return NSRect(
            x: centerX - target.width / 2,
            y: topY - target.height,
            width: target.width,
            height: target.height
        )
    }

    private func screenFrame(for window: NSWindow) -> NSRect {
        if let screen = window.screen {
            return screen.frame
        }

        let windowCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) }) {
            return screen.frame
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.frame
        }

        return NSScreen.main?.frame ?? window.frame
    }

    private var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: ui.expandedHeight)
    }
}
