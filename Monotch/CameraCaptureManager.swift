@preconcurrency import AVFoundation
import AppKit
import Combine
import CoreImage
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

struct CameraCaptureItem: Identifiable, Equatable {
    enum Kind: String, Codable {
        case photo
        case movie
    }

    let id: UUID
    let url: URL
    let kind: Kind

    init(id: UUID = UUID(), url: URL, kind: Kind) {
        self.id = id
        self.url = url
        self.kind = kind
    }

    var displayName: String {
        url.lastPathComponent
    }
}

final class CameraCaptureManager: NSObject, ObservableObject {
    static let shared = CameraCaptureManager()

    @Published var isRecording = false
    @Published private(set) var isPreviewReady = false
    @Published private(set) var previewErrorMessage: String?
    @Published var captures: [CameraCaptureItem] = [] {
        didSet { saveCapturesIfNeeded() }
    }

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private let sessionQueue = DispatchQueue(label: "fatihyavuz.Monotch.camera-session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var pendingPhotoFallbacksBySettingsID: [Int64: PendingPhotoFallback] = [:]
    private var recordingAspectRatiosByPath: [String: CGFloat] = [:]
    private var frameRecordingWriter: AVAssetWriter?
    private var frameRecordingInput: AVAssetWriterInput?
    private var frameRecordingAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameRecordingURL: URL?
    private var frameRecordingAspectRatio: CGFloat?
    private var frameRecordingOutputSize: CGSize = .zero
    private var frameRecordingHasVisibleStartFrame = false
    private var latestVideoPixelBuffer: CVPixelBuffer?
    private var previewHasVisibleFrame = false
    private var previewVisibleFrameCount = 0
    private var previewWarmupToken = 0
    private var didConfigureSession = false
    private var permissionDenied = false
    private var isRestoringCaptures = false

    private struct PendingPhotoFallback {
        let aspectRatio: CGFloat?
    }

    private override init() {
        super.init()
        loadCaptures()
    }

    func attachPreview(to layer: CALayer, frame: CGRect) {
        let previewLayer: AVCaptureVideoPreviewLayer
        if let existingPreviewLayer = self.previewLayer {
            previewLayer = existingPreviewLayer
        } else {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer
        }

        if previewLayer.superlayer !== layer {
            previewLayer.removeFromSuperlayer()
            hidePreviewLayerForWarmup(previewLayer)
            layer.insertSublayer(previewLayer, at: 0)
        }

        previewLayer.frame = frame
        startIfAllowed()
    }

    func updatePreviewFrame(_ frame: CGRect) {
        previewLayer?.frame = frame
    }

    func startIfAllowed() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setPreviewError(nil)
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionDenied = !granted
                    if granted {
                        self?.setPreviewError(nil)
                        self?.configureAndStart()
                    } else {
                        self?.setPreviewError("Camera access denied")
                        self?.markPreviewUnavailable()
                        self?.previewLayer?.removeFromSuperlayer()
                        self?.previewLayer = nil
                    }
                }
            }
        default:
            permissionDenied = true
            setPreviewError("Camera access denied")
            markPreviewUnavailable()
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func detachPreview(shouldStopSession: Bool) {
        markPreviewUnavailable()
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        if shouldStopSession {
            stopAfterPreviewDetach()
        }
    }

    private func stopAfterPreviewDetach() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.previewLayer == nil else { return }

            self.sessionQueue.async { [session = self.session, movieOutput = self.movieOutput, manager = self] in
                if movieOutput.isRecording || manager.frameRecordingURL != nil {
                    return
                }

                if session.isRunning {
                    session.stopRunning()
                }
            }
        }
    }

    func takePhoto(aspectRatio: CGFloat? = nil) {
        startIfAllowed()

        sessionQueue.async { [weak self] in
            guard let self, self.didConfigureSession else { return }

            self.syncToSystemPreferredCameraIfNeeded()
            let sanitizedAspectRatio = self.sanitizedAspectRatio(aspectRatio)

            if self.shouldPreferVideoFramePhotoFallback(),
               self.captureLatestVideoFramePhoto(aspectRatio: sanitizedAspectRatio) {
                return
            }

            guard self.photoOutput.connection(with: .video) != nil else {
                _ = self.captureLatestVideoFramePhoto(aspectRatio: sanitizedAspectRatio)
                return
            }

            let settings = self.simplePhotoSettings()
            self.pendingPhotoFallbacksBySettingsID[settings.uniqueID] = PendingPhotoFallback(aspectRatio: sanitizedAspectRatio)
            self.schedulePhotoFallback(settingsID: settings.uniqueID)
            self.mirrorConnection(self.photoOutput.connection(with: .video))
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording() {
        if movieOutput.isRecording || isRecording || frameRecordingURL != nil {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording(aspectRatio: CGFloat? = nil) {
        startIfAllowed()

        sessionQueue.async { [weak self] in
            guard let self, self.didConfigureSession else { return }

            guard self.movieOutput.isRecording == false,
                  self.frameRecordingURL == nil else {
                return
            }

            self.prepareSessionForRecording()

            self.frameRecordingURL = self.makeCaptureURL(kind: .movie)
            self.frameRecordingAspectRatio = self.sanitizedAspectRatio(aspectRatio)
            self.frameRecordingWriter = nil
            self.frameRecordingInput = nil
            self.frameRecordingAdaptor = nil
            self.frameRecordingOutputSize = .zero
            self.frameRecordingHasVisibleStartFrame = false
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
                return
            }

            self.finishFrameRecording()
        }
    }

    func deleteCapture(_ item: CameraCaptureItem) {
        DispatchQueue.main.async {
            self.captures.removeAll { $0.id == item.id }
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    func clearCaptures() {
        DispatchQueue.main.async {
            let urls = self.captures.map(\.url)
            self.captures = []
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func switchCamera() {
        startIfAllowed()

        sessionQueue.async { [weak self] in
            guard let self, self.didConfigureSession, self.movieOutput.isRecording == false else { return }

            let devices = self.availableVideoDevices()
            guard devices.count > 1 else { return }

            let currentID = self.currentVideoInput?.device.uniqueID
            let currentIndex = devices.firstIndex { $0.uniqueID == currentID } ?? 0
            let nextDevice = devices[(currentIndex + 1) % devices.count]

            self.setUserPreferredCamera(nextDevice)
            self.replaceVideoInput(with: nextDevice)
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.didConfigureSession == false {
                self.configureSession()
                self.didConfigureSession = true
            } else {
                self.syncToSystemPreferredCameraIfNeeded()
            }

            if self.session.isRunning == false {
                self.session.startRunning()
            }
        }
    }

    private func hidePreviewLayerForWarmup(_ previewLayer: AVCaptureVideoPreviewLayer) {
        markPreviewUnavailable()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.opacity = 0
        CATransaction.commit()
    }

    private func markPreviewUnavailable() {
        previewWarmupToken += 1
        previewHasVisibleFrame = false
        previewVisibleFrameCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.isPreviewReady = false
        }
    }

    private func setPreviewError(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.previewErrorMessage = message
        }
    }

    private func revealPreviewLayerAfterVisibleFrame() {
        let token = previewWarmupToken

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.previewWarmupToken == token,
                  let previewLayer = self.previewLayer else {
                return
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.opacity = 1
            CATransaction.commit()
            self.previewErrorMessage = nil
            self.isPreviewReady = true
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = preferredVideoDevice(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            setPreviewError("Camera unavailable")
            return
        }

        session.addInput(input)
        currentVideoInput = input

        setVideoFrameCaptureEnabled(true, wrapInConfiguration: false)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            configurePhotoOutputForSimpleCapture()
            mirrorConnection(photoOutput.connection(with: .video))
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            mirrorConnection(movieOutput.connection(with: .video))
        }

        applyBestSessionPreset()
    }

    private func mirrorConnection(_ connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }

    private func preferredVideoDevice() -> AVCaptureDevice? {
        if #available(macOS 13.0, *),
           let preferredCamera = AVCaptureDevice.systemPreferredCamera,
           preferredCamera.hasMediaType(.video) {
            return preferredCamera
        }

        return availableVideoDevices().first ?? AVCaptureDevice.default(for: .video)
    }

    private func availableVideoDevices() -> [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }

        var devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices

        if #available(macOS 13.0, *),
           let preferredCamera = AVCaptureDevice.systemPreferredCamera,
           preferredCamera.hasMediaType(.video),
           devices.contains(where: { $0.uniqueID == preferredCamera.uniqueID }) == false {
            devices.insert(preferredCamera, at: 0)
        }

        var seen = Set<String>()
        return devices.filter { device in
            guard seen.contains(device.uniqueID) == false else { return false }
            seen.insert(device.uniqueID)
            return true
        }
    }

    private func setUserPreferredCamera(_ device: AVCaptureDevice) {
        if #available(macOS 13.0, *) {
            AVCaptureDevice.userPreferredCamera = device
        }
    }

    private func syncToSystemPreferredCameraIfNeeded() {
        guard movieOutput.isRecording == false, let preferredDevice = preferredVideoDevice() else { return }
        guard currentVideoInput?.device.uniqueID != preferredDevice.uniqueID else { return }
        replaceVideoInput(with: preferredDevice)
    }

    private func replaceVideoInput(with device: AVCaptureDevice) {
        guard movieOutput.isRecording == false,
              currentVideoInput?.device.uniqueID != device.uniqueID,
              let nextInput = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if let previewLayer {
            hidePreviewLayerForWarmup(previewLayer)
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previousInput = currentVideoInput
        if let previousInput {
            session.removeInput(previousInput)
        }

        if session.canAddInput(nextInput) {
            session.addInput(nextInput)
            currentVideoInput = nextInput
            applyBestSessionPreset()
        } else if let previousInput, session.canAddInput(previousInput) {
            session.addInput(previousInput)
            currentVideoInput = previousInput
        }

        mirrorConnection(photoOutput.connection(with: .video))
        mirrorConnection(movieOutput.connection(with: .video))
        mirrorConnection(videoDataOutput.connection(with: .video))
    }

    private func setVideoFrameCaptureEnabled(_ isEnabled: Bool, wrapInConfiguration: Bool = true) {
        if wrapInConfiguration {
            session.beginConfiguration()
        }
        defer {
            if wrapInConfiguration {
                session.commitConfiguration()
            }
        }

        if isEnabled {
            guard session.outputs.contains(videoDataOutput) == false,
                  session.canAddOutput(videoDataOutput) else {
                return
            }

            configureVideoDataOutput()
            session.addOutput(videoDataOutput)
            mirrorConnection(videoDataOutput.connection(with: .video))
        } else if session.outputs.contains(videoDataOutput) {
            session.removeOutput(videoDataOutput)
            latestVideoPixelBuffer = nil
        }
    }

    private func prepareSessionForRecording() {
        guard session.outputs.contains(videoDataOutput) == false else { return }

        session.beginConfiguration()
        setVideoFrameCaptureEnabled(true, wrapInConfiguration: false)
        session.commitConfiguration()
    }

    private func restoreSessionAfterRecording() {
        guard session.outputs.contains(videoDataOutput) == false else { return }

        session.beginConfiguration()
        setVideoFrameCaptureEnabled(true, wrapInConfiguration: false)
        session.commitConfiguration()
    }

    private func applyBestSessionPreset() {
        let presets: [AVCaptureSession.Preset] = [.photo, .high, .medium]
        for preset in presets where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            return
        }
    }

    private func configurePhotoOutputForSimpleCapture() {
        if #available(macOS 13.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        if #available(macOS 14.0, *) {
            if photoOutput.isResponsiveCaptureSupported {
                photoOutput.isResponsiveCaptureEnabled = false
            }

            if photoOutput.isZeroShutterLagSupported {
                photoOutput.isZeroShutterLagEnabled = false
            }
        }

        if #available(macOS 15.0, *) {
            if photoOutput.isConstantColorSupported {
                photoOutput.isConstantColorEnabled = false
            }
        }
    }

    private func configureVideoDataOutput() {
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    }

    private func shouldPreferVideoFramePhotoFallback() -> Bool {
        guard let device = currentVideoInput?.device else { return false }

        if #available(macOS 13.0, *), device.isContinuityCamera {
            return true
        }

        if #available(macOS 14.0, *) {
            return device.deviceType == .continuityCamera
        }

        return false
    }

    private func simplePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        let availableCodecs = photoOutput.availablePhotoCodecTypes
        if availableCodecs.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else if availableCodecs.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }

        if #available(macOS 13.0, *) {
            settings.photoQualityPrioritization = .quality
        }

        if #available(macOS 15.0, *) {
            settings.isConstantColorEnabled = false
            settings.isConstantColorFallbackPhotoDeliveryEnabled = false
        }

        return settings
    }

    private enum CaptureKind {
        case photo
        case movie
    }

    private func addCapture(url: URL, kind: CameraCaptureItem.Kind) {
        DispatchQueue.main.async {
            let item = CameraCaptureItem(url: url, kind: kind)
            self.captures = Array(([item] + self.captures).prefix(24))
        }
    }

    private func makeCaptureURL(kind: CaptureKind) -> URL {
        let directory: URL
        let filename: String
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = formatter.string(from: Date())

        switch kind {
        case .photo:
            directory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            filename = "Monotch Photo \(stamp).jpg"
        case .movie:
            directory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            filename = "Monotch Recording \(stamp).mov"
        }

        return directory.appendingPathComponent(filename)
    }

    private func makeRawRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Monotch Raw Recording \(UUID().uuidString).mov")
    }

    private func copyRawRecording(_ sourceURL: URL, to destinationURL: URL, completion: @escaping (URL) -> Void) {
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            try? FileManager.default.removeItem(at: sourceURL)
            completion(destinationURL)
        } catch {
            NSLog("Monotch video copy fallback failed: \(error.localizedDescription)")
            completion(sourceURL)
        }
    }

    private func appendFrameRecordingSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let outputURL = frameRecordingURL,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return }

        if frameRecordingHasVisibleStartFrame == false {
            guard pixelBufferHasVisiblePixels(pixelBuffer) else { return }
            frameRecordingHasVisibleStartFrame = true
        }

        if frameRecordingWriter == nil {
            configureFrameRecordingWriter(
                outputURL: outputURL,
                pixelBuffer: pixelBuffer,
                startTime: presentationTime
            )
        }

        guard let input = frameRecordingInput,
              let adaptor = frameRecordingAdaptor,
              input.isReadyForMoreMediaData,
              let recordingPixelBuffer = makeRecordingPixelBuffer(from: pixelBuffer, adaptor: adaptor) else {
            return
        }

        adaptor.append(recordingPixelBuffer, withPresentationTime: presentationTime)
    }

    private func configureFrameRecordingWriter(
        outputURL: URL,
        pixelBuffer: CVPixelBuffer,
        startTime: CMTime
    ) {
        let sourceSize = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
        let outputCrop = recordingCropRect(
            width: sourceSize.width,
            height: sourceSize.height,
            aspectRatio: frameRecordingAspectRatio
        )
        let outputSize = outputCrop.size
        guard outputSize.width >= 2, outputSize.height >= 2 else { return }

        do {
            try? FileManager.default.removeItem(at: outputURL)

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let bitrate = max(4_000_000, Int(outputSize.width * outputSize.height * 10))
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(outputSize.width),
                AVVideoHeightKey: Int(outputSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(outputSize.width),
                    kCVPixelBufferHeightKey as String: Int(outputSize.height),
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
            )

            guard writer.canAdd(input) else { return }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)

            frameRecordingWriter = writer
            frameRecordingInput = input
            frameRecordingAdaptor = adaptor
            frameRecordingOutputSize = outputSize
        } catch {
            NSLog("Monotch frame recording setup failed: \(error.localizedDescription)")
            finishFrameRecording()
        }
    }

    private func makeRecordingPixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceExtent = sourceImage.extent
        let crop = recordingCropRect(
            width: sourceExtent.width,
            height: sourceExtent.height,
            aspectRatio: frameRecordingAspectRatio
        ).offsetBy(dx: sourceExtent.minX, dy: sourceExtent.minY)

        var outputPixelBuffer: CVPixelBuffer?
        if let pixelBufferPool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)
        }

        if outputPixelBuffer == nil {
            CVPixelBufferCreate(
                nil,
                Int(frameRecordingOutputSize.width),
                Int(frameRecordingOutputSize.height),
                kCVPixelFormatType_32BGRA,
                [
                    kCVPixelBufferCGImageCompatibilityKey: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey: true
                ] as CFDictionary,
                &outputPixelBuffer
            )
        }

        guard let outputPixelBuffer else { return nil }

        let outputImage = sourceImage
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

        ciContext.render(
            outputImage,
            to: outputPixelBuffer,
            bounds: CGRect(origin: .zero, size: frameRecordingOutputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return outputPixelBuffer
    }

    private func finishFrameRecording() {
        let writer = frameRecordingWriter
        let input = frameRecordingInput
        let outputURL = frameRecordingURL

        frameRecordingWriter = nil
        frameRecordingInput = nil
        frameRecordingAdaptor = nil
        frameRecordingURL = nil
        frameRecordingAspectRatio = nil
        frameRecordingOutputSize = .zero
        frameRecordingHasVisibleStartFrame = false

        DispatchQueue.main.async {
            self.isRecording = false
        }
        restoreSessionAfterRecording()

        guard let writer, let input, let outputURL else {
            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return
        }

        input.markAsFinished()
        writer.finishWriting { [weak self] in
            if writer.status == .completed,
               self?.videoLikelyContainsVisibleFrame(outputURL) == true {
                self?.addCapture(url: outputURL, kind: .movie)
            } else {
                if let error = writer.error {
                    NSLog("Monotch frame recording failed: \(error.localizedDescription)")
                } else {
                    NSLog("Monotch frame recording produced a blank video")
                }
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
    }

    private func recordingCropRect(width: CGFloat, height: CGFloat, aspectRatio: CGFloat?) -> CGRect {
        let crop = cropRect(width: width, height: height, aspectRatio: aspectRatio ?? max(width / max(height, 1), 0.1))
        let evenWidth = max(2, floor(crop.width / 2) * 2)
        let evenHeight = max(2, floor(crop.height / 2) * 2)

        return CGRect(
            x: floor((width - evenWidth) / 2),
            y: floor((height - evenHeight) / 2),
            width: evenWidth,
            height: evenHeight
        )
    }

    private func schedulePhotoFallback(settingsID: Int64) {
        sessionQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self,
                  let pending = self.pendingPhotoFallbacksBySettingsID.removeValue(forKey: settingsID) else {
                return
            }

            _ = self.captureLatestVideoFramePhoto(aspectRatio: pending.aspectRatio)
        }
    }

    @discardableResult
    private func captureLatestVideoFramePhoto(aspectRatio: CGFloat?) -> Bool {
        guard let pixelBuffer = latestVideoPixelBuffer else {
            NSLog("Monotch photo fallback failed: no video frame available")
            return false
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent),
              let jpegData = jpegPhotoData(from: cgImage, aspectRatio: aspectRatio) else {
            NSLog("Monotch photo fallback failed: could not create image data")
            return false
        }

        do {
            let url = makeCaptureURL(kind: .photo)
            try jpegData.write(to: url, options: .atomic)
            addCapture(url: url, kind: .photo)
            return true
        } catch {
            NSLog("Monotch photo fallback failed: \(error.localizedDescription)")
            return false
        }
    }

    private func sanitizedAspectRatio(_ aspectRatio: CGFloat?) -> CGFloat? {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0.1 else { return nil }
        return min(4.0, max(0.25, aspectRatio))
    }

    private func jpegPhotoData(from image: CGImage, aspectRatio: CGFloat?) -> Data? {
        let outputImage: CGImage
        if let aspectRatio = sanitizedAspectRatio(aspectRatio),
           let croppedImage = image.cropping(to: cropRect(
            width: CGFloat(image.width),
            height: CGFloat(image.height),
            aspectRatio: aspectRatio
           )) {
            outputImage = croppedImage
        } else {
            outputImage = image
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
        CGImageDestinationAddImage(destination, outputImage, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    private func croppedPhotoData(from data: Data, aspectRatio: CGFloat?) -> Data {
        guard let aspectRatio = sanitizedAspectRatio(aspectRatio),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let croppedImage = image.cropping(to: cropRect(
                width: CGFloat(image.width),
                height: CGFloat(image.height),
                aspectRatio: aspectRatio
              )) else {
            return data
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return data
        }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        CGImageDestinationAddImage(destination, croppedImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return data }
        return outputData as Data
    }

    private func cropRect(width: CGFloat, height: CGFloat, aspectRatio: CGFloat) -> CGRect {
        guard width > 0, height > 0 else { return .zero }

        let sourceAspect = width / height
        let cropSize: CGSize
        if sourceAspect > aspectRatio {
            cropSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            cropSize = CGSize(width: width, height: width / aspectRatio)
        }

        return CGRect(
            x: (width - cropSize.width) / 2,
            y: (height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        ).integral
    }

    private func cropRawRecording(
        _ sourceURL: URL,
        to destinationURL: URL,
        aspectRatio: CGFloat?,
        completion: @escaping (URL) -> Void
    ) {
        guard let aspectRatio = sanitizedAspectRatio(aspectRatio) else {
            copyRawRecording(sourceURL, to: destinationURL, completion: completion)
            return
        }

        let asset = AVAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            copyRawRecording(sourceURL, to: destinationURL, completion: completion)
            return
        }

        let naturalSize = CGSize(
            width: abs(videoTrack.naturalSize.width),
            height: abs(videoTrack.naturalSize.height)
        )
        let renderCrop = cropRect(width: naturalSize.width, height: naturalSize.height, aspectRatio: aspectRatio)
        guard renderCrop.width > 0, renderCrop.height > 0 else {
            copyRawRecording(sourceURL, to: destinationURL, completion: completion)
            return
        }

        let videoComposition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            let sourceImage = request.sourceImage
            let sourceExtent = sourceImage.extent
            guard sourceExtent.width > 0, sourceExtent.height > 0 else {
                request.finish(with: sourceImage, context: nil)
                return
            }

            let crop = self.cropRect(
                width: sourceExtent.width,
                height: sourceExtent.height,
                aspectRatio: aspectRatio
            ).offsetBy(dx: sourceExtent.minX, dy: sourceExtent.minY)
            let croppedImage = sourceImage
                .cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

            request.finish(with: croppedImage, context: nil)
        })
        videoComposition.renderSize = renderCrop.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        try? FileManager.default.removeItem(at: destinationURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            copyRawRecording(sourceURL, to: destinationURL, completion: completion)
            return
        }

        exporter.outputURL = destinationURL
        exporter.outputFileType = .mov
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = false
        exporter.exportAsynchronously {
            if exporter.status == .completed,
               self.videoLikelyContainsVisibleFrame(destinationURL) {
                try? FileManager.default.removeItem(at: sourceURL)
                completion(destinationURL)
            } else {
                if exporter.status == .completed {
                    NSLog("Monotch video crop produced a blank frame; keeping raw recording instead")
                }
                try? FileManager.default.removeItem(at: destinationURL)
                self.copyRawRecording(sourceURL, to: destinationURL, completion: completion)
            }
        }
    }

    private func pixelBufferHasVisiblePixels(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return true }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow > 0 else { return false }

        let sampleColumns = min(24, width)
        let sampleRows = min(24, height)
        var totalLuma = 0
        var visibleSamples = 0
        var strongSamples = 0
        var samples = 0

        for rowIndex in 0..<sampleRows {
            let y = min(height - 1, rowIndex * height / sampleRows)
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)

            for columnIndex in 0..<sampleColumns {
                let x = min(width - 1, columnIndex * width / sampleColumns)
                let pixelIndex = x * 4
                let blue = Int(row[pixelIndex])
                let green = Int(row[pixelIndex + 1])
                let red = Int(row[pixelIndex + 2])
                let luma = (red * 299 + green * 587 + blue * 114) / 1000
                totalLuma += luma
                if luma > 18 {
                    visibleSamples += 1
                }
                if luma > 36 {
                    strongSamples += 1
                }
                samples += 1
            }
        }

        guard samples > 0 else { return false }
        let averageLuma = Double(totalLuma) / Double(samples)
        let visibleRatio = Double(visibleSamples) / Double(samples)
        let strongRatio = Double(strongSamples) / Double(samples)

        return (averageLuma > 16 && visibleRatio > 0.14) || visibleRatio > 0.26 || strongRatio > 0.18
    }

    private func videoLikelyContainsVisibleFrame(_ url: URL) -> Bool {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 48, height: 48)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        let sampleTimes = [
            CMTime(seconds: 0.08, preferredTimescale: 600),
            CMTime(seconds: 0.35, preferredTimescale: 600),
            CMTime(seconds: 0.8, preferredTimescale: 600)
        ]

        for sampleTime in sampleTimes {
            if let image = try? generator.copyCGImage(at: sampleTime, actualTime: nil),
               imageHasVisiblePixels(image) {
                return true
            }
        }

        return false
    }

    private func imageHasVisiblePixels(_ image: CGImage) -> Bool {
        let width = 16
        let height = 16
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuma = 0
        var maxLuma = 0
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let luma = (red * 299 + green * 587 + blue * 114) / 1000
            totalLuma += luma
            maxLuma = max(maxLuma, luma)
        }

        let averageLuma = totalLuma / (width * height)
        return averageLuma > 4 || maxLuma > 18
    }
}

private extension CameraCaptureManager {
    struct StoredCapture: Codable {
        var id: UUID
        var path: String
        var kind: CameraCaptureItem.Kind
    }

    var capturesURL: URL {
        applicationSupportDirectory.appendingPathComponent("camera-captures.json")
    }

    var applicationSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent("Monotch", isDirectory: true)
    }

    func loadCaptures() {
        isRestoringCaptures = true
        defer { isRestoringCaptures = false }

        guard let data = try? Data(contentsOf: capturesURL),
              let storedCaptures = try? JSONDecoder().decode([StoredCapture].self, from: data) else {
            return
        }

        captures = storedCaptures.compactMap { item in
            let url = URL(fileURLWithPath: item.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return CameraCaptureItem(id: item.id, url: url, kind: item.kind)
        }
    }

    func saveCapturesIfNeeded() {
        guard isRestoringCaptures == false else { return }

        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            let storedCaptures = captures.map { item in
                StoredCapture(id: item.id, path: item.url.path, kind: item.kind)
            }
            let data = try JSONEncoder().encode(storedCaptures)
            try data.write(to: capturesURL, options: .atomic)
        } catch {
            NSLog("Monotch camera captures save failed: \(error.localizedDescription)")
        }
    }
}

extension CameraCaptureManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let pending = pendingPhotoFallbacksBySettingsID.removeValue(forKey: photo.resolvedSettings.uniqueID) else {
            return
        }

        if let error {
            NSLog("Monotch photo capture failed: \(error.localizedDescription)")
            _ = captureLatestVideoFramePhoto(aspectRatio: pending.aspectRatio)
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            NSLog("Monotch photo capture failed: no file data returned")
            _ = captureLatestVideoFramePhoto(aspectRatio: pending.aspectRatio)
            return
        }

        do {
            let url = makeCaptureURL(kind: .photo)
            try croppedPhotoData(from: data, aspectRatio: pending.aspectRatio).write(to: url, options: .atomic)
            addCapture(url: url, kind: .photo)
        } catch {
            NSLog("Monotch photo capture failed: \(error.localizedDescription)")
            _ = captureLatestVideoFramePhoto(aspectRatio: pending.aspectRatio)
        }
    }
}

extension CameraCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestVideoPixelBuffer = pixelBuffer

        if previewHasVisibleFrame == false {
            if pixelBufferHasVisiblePixels(pixelBuffer) {
                previewVisibleFrameCount += 1
            } else {
                previewVisibleFrameCount = 0
            }

            if previewVisibleFrameCount >= 4 {
                previewHasVisibleFrame = true
                revealPreviewLayerAfterVisibleFrame()
            }
        }

        if frameRecordingURL != nil {
            appendFrameRecordingSampleBuffer(sampleBuffer)
        }
    }
}

extension CameraCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
        }

        sessionQueue.async { [weak self] in
            self?.restoreSessionAfterRecording()
        }

        let recordingError = error.map { $0 as NSError }
        let recordingFinishedSuccessfully = error == nil
            || (recordingError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)

        if recordingFinishedSuccessfully == false, let error {
            NSLog("Monotch video recording failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: outputFileURL)
        } else {
            let aspectRatio = recordingAspectRatiosByPath.removeValue(forKey: outputFileURL.path)
            let destinationURL = makeCaptureURL(kind: .movie)
            cropRawRecording(outputFileURL, to: destinationURL, aspectRatio: aspectRatio) { [weak self] recordingURL in
                self?.addCapture(url: recordingURL, kind: .movie)
            }
        }
    }
}
