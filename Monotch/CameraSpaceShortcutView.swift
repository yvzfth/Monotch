import AppKit
import SwiftUI

struct CameraSpaceShortcutView: NSViewRepresentable {
    let manager: CameraCaptureManager
    let aspectRatio: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager, aspectRatio: aspectRatio)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.aspectRatio = aspectRatio
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let manager: CameraCaptureManager
        var aspectRatio: CGFloat
        private var keyDownMonitor: Any?
        private var keyUpMonitor: Any?
        private var isSpacePressed = false
        private var didStartRecording = false
        private var pendingRecordStart: DispatchWorkItem?

        init(manager: CameraCaptureManager, aspectRatio: CGFloat) {
            self.manager = manager
            self.aspectRatio = aspectRatio
        }

        func start() {
            guard keyDownMonitor == nil, keyUpMonitor == nil else { return }

            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isSpaceEvent(event) else { return event }
                self.handleSpaceDown()
                return nil
            }

            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self, self.isSpaceEvent(event) else { return event }
                self.handleSpaceUp()
                return nil
            }
        }

        func stop() {
            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
            }
            if let keyUpMonitor {
                NSEvent.removeMonitor(keyUpMonitor)
            }

            keyDownMonitor = nil
            keyUpMonitor = nil
            pendingRecordStart?.cancel()
            pendingRecordStart = nil

            if didStartRecording {
                manager.stopRecording()
            }

            isSpacePressed = false
            didStartRecording = false
        }

        private func isSpaceEvent(_ event: NSEvent) -> Bool {
            event.keyCode == 49
        }

        private func handleSpaceDown() {
            guard isSpacePressed == false else { return }

            isSpacePressed = true
            didStartRecording = false

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isSpacePressed else { return }
                self.didStartRecording = true
                self.manager.startRecording(aspectRatio: self.aspectRatio)
            }

            pendingRecordStart = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
        }

        private func handleSpaceUp() {
            guard isSpacePressed else { return }

            isSpacePressed = false
            pendingRecordStart?.cancel()
            pendingRecordStart = nil

            if didStartRecording {
                manager.stopRecording()
            } else {
                manager.takePhoto(aspectRatio: aspectRatio)
            }

            didStartRecording = false
        }
    }
}
