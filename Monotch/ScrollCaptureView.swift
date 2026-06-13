import SwiftUI
import AppKit

struct ScrollCaptureView: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let view = ScrollCaptureNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class ScrollCaptureNSView: NSView {
    var onScroll: ((CGFloat, CGFloat, CGPoint) -> Void)?
    private var scrollMonitor: Any?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, convert(event.locationInWindow, from: nil))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeScrollMonitor()
        } else {
            installScrollMonitorIfNeeded()
        }
    }

    deinit {
        removeScrollMonitor()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let window = self.window,
                  let eventWindow = event.window,
                  eventWindow === window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                return event
            }

            self.onScroll?(
                event.scrollingDeltaX,
                event.scrollingDeltaY,
                self.convert(event.locationInWindow, from: nil)
            )
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}
