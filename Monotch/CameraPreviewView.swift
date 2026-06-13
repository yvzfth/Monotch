import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let manager: CameraCaptureManager

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(manager: manager)
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.startIfAllowed()
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.detach()
    }
}

final class CameraPreviewNSView: NSView {
    private let manager: CameraCaptureManager

    init(manager: CameraCaptureManager) {
        self.manager = manager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        startIfAllowed()
    }

    override init(frame frameRect: NSRect) {
        self.manager = .shared
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        startIfAllowed()
    }

    required init?(coder: NSCoder) {
        self.manager = .shared
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        startIfAllowed()
    }

    override func layout() {
        super.layout()
        manager.updatePreviewFrame(bounds)
    }

    func startIfAllowed() {
        guard let layer else { return }
        manager.attachPreview(to: layer, frame: bounds)
    }

    func detach() {
        manager.detachPreview(shouldStopSession: true)
    }
}
