import AppKit
import Foundation

struct MediaBridgePayload {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var bundleID: String
    var appName: String
    var artwork: NSImage?
}

/// Reads system-wide now-playing state through the private MediaRemote framework.
///
/// Since macOS 15.4 MediaRemote only answers Apple platform binaries, so the
/// bundled MonotchMediaBridge.dylib is loaded into `/usr/bin/perl` (an Apple
/// signed binary) and streams line-delimited JSON back over stdout. This is the
/// same mechanism the macOS menu bar uses conceptually: it sees every player,
/// including web players in any browser, without per-browser scripting access.
final class MediaBridgeClient {
    private static let perlLoaderScript = """
    use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0]) or die "load failed\\n"; my $s = DynaLoader::dl_find_symbol($h, "monotch_main") or die "symbol missing\\n"; DynaLoader::dl_install_xsub("main::bridge_main", $s); main::bridge_main();
    """

    private var process: Process?
    private var stdinPipe: Pipe?
    private var lineBuffer = Data()
    private var onState: ((MediaBridgePayload) -> Void)?
    private var isStopped = false
    private var cachedArtwork: (hash: Int, image: NSImage)?
    private var lastPayloadDate: Date?

    var isHealthy: Bool {
        guard let lastPayloadDate else { return false }
        return Date().timeIntervalSince(lastPayloadDate) < 15
    }

    private static var bridgeLibraryURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("MonotchMediaBridge.dylib"),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    deinit {
        stop()
    }

    func start(onState: @escaping (MediaBridgePayload) -> Void) {
        self.onState = onState
        isStopped = false
        launchStreamProcess()
    }

    func stop() {
        isStopped = true
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
    }

    func sendCommand(_ command: String) {
        runCommandProcess(environment: ["MONOTCH_MEDIA_COMMAND": command])
    }

    func seek(to position: Double) {
        runCommandProcess(environment: [
            "MONOTCH_MEDIA_COMMAND": "seek",
            "MONOTCH_MEDIA_POSITION": String(position)
        ])
    }

    private func launchStreamProcess() {
        guard isStopped == false,
              let bridgeURL = Self.bridgeLibraryURL,
              let bridgeProcess = makeBridgeProcess(mode: "stream", extraEnvironment: [:], libraryURL: bridgeURL) else {
            return
        }

        // The bridge exits when its stdin reaches EOF, so a held-open pipe ties
        // its lifetime to ours even if we die without terminating it.
        let inputPipe = Pipe()
        bridgeProcess.standardInput = inputPipe

        let outputPipe = Pipe()
        bridgeProcess.standardOutput = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            DispatchQueue.main.async {
                self?.consumeStreamData(data)
            }
        }

        bridgeProcess.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.launchStreamProcess()
            }
        }

        do {
            try bridgeProcess.run()
            process = bridgeProcess
            stdinPipe = inputPipe
        } catch {
            process = nil
            stdinPipe = nil
        }
    }

    private func makeBridgeProcess(
        mode: String,
        extraEnvironment: [String: String],
        libraryURL: URL
    ) -> Process? {
        let bridgeProcess = Process()
        bridgeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        bridgeProcess.arguments = ["-e", Self.perlLoaderScript, "--", libraryURL.path]

        var environment = ProcessInfo.processInfo.environment
        environment["MONOTCH_MEDIA_MODE"] = mode
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        bridgeProcess.environment = environment
        bridgeProcess.standardError = FileHandle.nullDevice
        return bridgeProcess
    }

    private func runCommandProcess(environment: [String: String]) {
        guard let bridgeURL = Self.bridgeLibraryURL,
              let commandProcess = makeBridgeProcess(mode: "command", extraEnvironment: environment, libraryURL: bridgeURL) else {
            return
        }

        commandProcess.standardOutput = FileHandle.nullDevice
        try? commandProcess.run()
    }

    private func consumeStreamData(_ data: Data) {
        lineBuffer.append(data)

        while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineIndex)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIndex)
            handleLine(lineData)
        }
    }

    private func handleLine(_ lineData: Data) {
        guard lineData.isEmpty == false,
              let object = try? JSONSerialization.jsonObject(with: lineData),
              let json = object as? [String: Any],
              (json["event"] as? String) == "state" else {
            return
        }

        lastPayloadDate = Date()

        var artwork: NSImage?
        let artworkHash = json["artworkHash"] as? Int
        if let base64 = json["artworkB64"] as? String,
           let artworkData = Data(base64Encoded: base64),
           let image = NSImage(data: artworkData) {
            artwork = image
            if let artworkHash {
                cachedArtwork = (artworkHash, image)
            }
        } else if let artworkHash, let cachedArtwork, cachedArtwork.hash == artworkHash {
            artwork = cachedArtwork.image
        }

        let payload = MediaBridgePayload(
            title: (json["title"] as? String) ?? "",
            artist: (json["artist"] as? String) ?? "",
            album: (json["album"] as? String) ?? "",
            duration: (json["duration"] as? Double) ?? 0,
            position: (json["position"] as? Double) ?? 0,
            isPlaying: (json["playing"] as? Bool) ?? ((json["playing"] as? Int) == 1),
            bundleID: (json["bundleID"] as? String) ?? "",
            appName: (json["appName"] as? String) ?? "",
            artwork: artwork
        )

        onState?(payload)
    }
}
