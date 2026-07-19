import Cocoa
import SwiftUI
import Combine

private final class NotchPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// The panel window is always sized to fit the fully expanded island (to avoid
// the AppKit resize/constraints crash — see NotchWindowController.windowSize),
// but most of that frame is empty margin for the shadow. Without this override
// the transparent margin still swallows clicks meant for whatever is behind it
// (other app windows, our own Settings/Help windows), because AppKit hit-tests
// the window's full rectangle regardless of what's actually drawn there.
private final class NotchHostingView: NSHostingView<NotchIslandContainerView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let ui = NotchUIState.shared
        let size = ui.isExpanded
            ? CGSize(width: NotchIslandMetrics.expandedWidth, height: ui.expandedHeight)
            : NotchIslandMetrics.collapsedSize

        let originX = (bounds.width - size.width) / 2
        let originY = bounds.height - size.height
        let islandRect = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        let hitRect = islandRect.insetBy(dx: ui.isExpanded ? -2 : -8, dy: ui.isExpanded ? -2 : -6)

        guard hitRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
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

    // Window never resizes: it is always large enough for the fully expanded
    // island, and SwiftUI animates the island inside it. Resizing the window
    // in step with SwiftUI layout caused AppKit update-constraints loops.
    private let windowSize = CGSize(width: NotchIslandMetrics.expandedWidth + 80, height: 440)
    private let topOverlap: CGFloat = NotchIslandMetrics.topOverlap

    private init() {
        createWindowIfNeeded()
        startHoverMonitoring()
        ui.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                if expanded {
                    self?.startExpandedPointerWatchdog()
                } else {
                    self?.stopExpandedPointerWatchdog()
                }
                self?.updateClickThrough()
            }
            .store(in: &cancellables)

        ui.$isInteractionHeld
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateClickThrough()
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
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
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

        let notchWidth: CGFloat = windowSize.width
        let notchHeight: CGFloat = windowSize.height

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
        let hosting = NotchHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.makeFirstResponder(hosting)

        self.window = window
        updateClickThrough()
    }

    private func startHoverMonitoring() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handlePointerMoved()
            return event
        }

        // Always-on global monitor: the panel window is much larger than the
        // visible island (margin for the shadow), and its low-alpha shadow
        // pixels would otherwise swallow clicks meant for windows behind it.
        // The window stays click-through except while the pointer is on the
        // island, and since tracking areas don't fire on a window that
        // ignores mouse events, this monitor is also what re-arms hover.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePointerMoved()
            }
        }
    }

    private func handlePointerMoved() {
        guard window?.isVisible == true else { return }

        updateClickThrough()

        guard ui.isInteractionHeld == false else { return }

        if isPointerInsideNotch() {
            pointerEnteredNotch()
        } else if ui.isExpanded {
            pointerLeftNotch()
        }
    }

    private func updateClickThrough() {
        guard let window else { return }

        let shouldIgnore = ui.isInteractionHeld == false && isPointerInsideNotch() == false
        if window.ignoresMouseEvents != shouldIgnore {
            window.ignoresMouseEvents = shouldIgnore
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
    }

    private func stopExpandedPointerWatchdog() {
        expandedPointerWatchdog?.invalidate()
        expandedPointerWatchdog = nil
        pendingCollapse?.cancel()
    }

    private func isPointerInsideNotch() -> Bool {
        let point = NSEvent.mouseLocation
        let hitFrame = islandFrame().insetBy(dx: ui.isExpanded ? -2 : -8, dy: ui.isExpanded ? -2 : -6)
        return hitFrame.contains(point)
    }

    // The island is pinned to the top-center of the fixed-size window.
    private func islandFrame() -> NSRect {
        guard let window else { return .zero }

        let size = ui.isExpanded
            ? CGSize(width: NotchIslandMetrics.expandedWidth, height: ui.expandedHeight)
            : NotchIslandMetrics.collapsedSize
        let windowFrame = window.frame

        return NSRect(
            x: windowFrame.midX - size.width / 2,
            y: windowFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func positionWindow() {
        guard let window else { return }

        let screenFrame = screenFrame(for: window)
        let notchWidth = windowSize.width
        let notchHeight = windowSize.height

        let originX = screenFrame.midX - notchWidth / 2
        let originY = screenFrame.maxY - notchHeight + topOverlap

        window.setFrame(
            NSRect(x: originX, y: originY, width: notchWidth, height: notchHeight),
            display: true
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
}
