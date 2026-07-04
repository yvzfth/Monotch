import Foundation
import Combine
import AppKit
import ApplicationServices
import CoreGraphics

struct InlineLyricsWindow: Equatable {
    var previous: String?
    var current: String
    var next: String?
}

final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published var title: String = "Not playing"
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var isPlaying: Bool = false
    @Published var sourceName: String = "Music"
    @Published var artwork: NSImage?
    @Published var duration: Double = 0
    @Published var playerPosition: Double = 0

    private var observers: [Any] = []
    private var lastKnownPlayer: PlayerApp = .music
    private var lastCommandTarget: PlaybackCommandTarget = .player(.music)
    private var progressTimer: Timer?
    private var lastProgressUpdate = Date()
    private var didRefreshNearTrackEnd = false
    private var lastNearTrackEndRefresh = Date.distantPast
    private var lastPreferredRefresh = Date.distantPast
    private var lastArtworkURL: URL?
    private var scriptCache: [String: NSAppleScript] = [:]
    private let spotifyAccessibility = SpotifyAccessibility()
    private let lyricsClient = LRCLIBLyricsClient()
    private var lyricsCache: [String: LyricsContent] = [:]

    private init() {
        startObservingSystemNowPlaying()
        startObservingPlayers()
        refreshFromPreferredNowPlaying(allowZeroReset: true)
        startProgressTimer()
    }

    deinit {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        progressTimer?.invalidate()
    }

    func previousTrack() {
        sendCommand("previous track", fallbackMediaKey: .previous)
    }

    func togglePlayPause() {
        sendCommand("playpause", fallbackMediaKey: .playPause)
    }

    func nextTrack() {
        sendCommand("next track", fallbackMediaKey: .next)
    }

    func currentOutputVolumeState() -> OutputVolumeState {
        guard let rawValue = runAppleScriptString("""
        set volumeSettings to get volume settings
        return (output volume of volumeSettings as text) & "|||" & (output muted of volumeSettings as text)
        """) else {
            return OutputVolumeState(level: 0.5, isMuted: false)
        }

        let parts = rawValue.components(separatedBy: "|||")
        let volume = Double(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 50
        let muted = parts.dropFirst().first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveContains("true") == true

        return OutputVolumeState(level: min(1, max(0, volume / 100)), isMuted: muted)
    }

    func setOutputVolumeLevel(_ level: Double) {
        let volume = Int((min(1, max(0, level)) * 100).rounded())
        _ = runAppleScriptCommand("""
        set volume output volume \(volume) output muted false
        """)
    }

    func setOutputMuted(_ isMuted: Bool) {
        _ = runAppleScriptCommand("""
        set volume output muted \(isMuted ? "true" : "false")
        """)
    }

    func currentTrackShareItems() -> [Any] {
        if let url = currentTrackShareURL() {
            return [url as NSURL]
        }

        return [currentTrackDisplayText as NSString]
    }

    @discardableResult
    func addCurrentTrackToSpotifyLikedSongs() -> String {
        guard PlayerApp.spotify.isRunning else {
            return "Spotify is not running"
        }

        let result = runAppleScriptString("""
        tell application "Spotify"
            if it is running then
                try
                    set likedState to starred of current track
                    if likedState is true then
                        return "already"
                    end if
                    set starred of current track to true
                    return "liked"
                on error
                    return ""
                end try
            end if
        end tell
        return ""
        """)

        switch result {
        case "liked":
            return "Added to liked songs"
        case "already":
            return "Already liked"
        default:
            return spotifyAccessibility.addCurrentTrackToLikedSongs()
        }
    }

    func inlineQueueItems() -> [String] {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              title != "Not playing" else {
            return ["No song playing"]
        }

        return [
            currentTrackDisplayText,
            "Up next is not exposed locally"
        ]
    }

    func loadInlineQueueItems(completion: @escaping ([String]) -> Void) {
        guard PlayerApp.spotify.isRunning else {
            completion(inlineQueueItems())
            return
        }

        spotifyAccessibility.loadQueue { [weak self] queueItems in
            DispatchQueue.main.async {
                guard let self else { return }

                if queueItems.isEmpty {
                    completion([
                        self.currentTrackDisplayText,
                        "Spotify queue is empty or not visible"
                    ])
                } else {
                    completion(queueItems)
                }
            }
        }
    }

    func inlineLyricsText() -> String {
        inlineLyricsWindow().current
    }

    func inlineLyricsWindow() -> InlineLyricsWindow {
        if let lyrics = currentTrackLyrics(), lyrics.isEmpty == false {
            return InlineLyricsWindow(previous: nil, current: lyrics, next: nil)
        }

        let lookup = currentLyricsLookup()
        if let cachedLyrics = lyricsCache[lookup.cacheKey],
           let lyricsWindow = compactLyricsWindow(cachedLyrics),
           lyricsWindow.current.isEmpty == false {
            return lyricsWindow
        }

        return InlineLyricsWindow(
            previous: nil,
            current: "Lyrics are not exposed locally by \(sourceName)",
            next: nil
        )
    }

    func loadInlineLyricsText(completion: @escaping (String) -> Void) {
        loadInlineLyricsWindow { lyricsWindow in
            completion(lyricsWindow.current)
        }
    }

    func loadInlineLyricsWindow(completion: @escaping (InlineLyricsWindow) -> Void) {
        if let lyrics = currentTrackLyrics(), lyrics.isEmpty == false {
            completion(InlineLyricsWindow(previous: nil, current: lyrics, next: nil))
            return
        }

        let lookup = currentLyricsLookup()
        guard lookup.isValid else {
            completion(InlineLyricsWindow(previous: nil, current: "No song playing", next: nil))
            return
        }

        if let cachedLyrics = lyricsCache[lookup.cacheKey],
           let lyricsWindow = compactLyricsWindow(cachedLyrics),
           lyricsWindow.current.isEmpty == false {
            completion(lyricsWindow)
            return
        }

        lyricsClient.fetchLyrics(for: lookup) { [weak self] content in
            DispatchQueue.main.async {
                guard let self else { return }

                if let content {
                    self.lyricsCache[lookup.cacheKey] = content
                    completion(
                        self.compactLyricsWindow(content)
                            ?? InlineLyricsWindow(previous: nil, current: "Lyrics not found", next: nil)
                    )
                } else {
                    completion(InlineLyricsWindow(previous: nil, current: "Lyrics not found", next: nil))
                }
            }
        }
    }

    func refreshNowPlaying() {
        refreshFromPreferredNowPlaying(allowZeroReset: false)
    }

    func refreshNowPlayingIfNeeded(minimumInterval: TimeInterval) {
        let now = Date()
        guard now.timeIntervalSince(lastPreferredRefresh) >= minimumInterval else { return }
        lastPreferredRefresh = now
        refreshFromPreferredNowPlaying(allowZeroReset: false)
    }

    func seek(to position: Double) {
        guard duration > 0 else { return }

        let target = max(0, min(position, duration))
        playerPosition = target
        lastProgressUpdate = Date()

        if lastCommandTarget == .systemMedia {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshPlaybackPosition(allowZeroReset: true)
            }
            return
        }

        if case let .browser(browser) = lastCommandTarget {
            _ = runAppleScriptCommand(browser.seekScript(position: target))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshPlaybackPosition(allowZeroReset: true)
            }
            return
        }

        let player = lastKnownPlayer.isRunning ? lastKnownPlayer : PlayerApp.allCases.first(where: \.isRunning) ?? lastKnownPlayer
        _ = runAppleScriptCommand("""
        tell application "\(player.scriptName)"
            set player position to \(target)
        end tell
        """)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refreshPlaybackPosition(allowZeroReset: true)
        }
    }

    private var currentTrackDisplayText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty || trimmedTitle == "Not playing" {
            return sourceName
        }

        return trimmedArtist.isEmpty ? trimmedTitle : "\(trimmedArtist) - \(trimmedTitle)"
    }

    private func currentTrackShareURL() -> URL? {
        switch lastCommandTarget {
        case .browser(let browser):
            return browserShareURL(from: browser)
        case .player(.spotify):
            return spotifyCurrentTrackURL()
        case .player(.music):
            return musicCurrentTrackURL()
        case .systemMedia:
            break
        }

        switch lastKnownPlayer {
        case .spotify:
            return spotifyCurrentTrackURL()
        case .music:
            return musicCurrentTrackURL()
        }
    }

    private func spotifyCurrentTrackURL() -> URL? {
        guard let rawValue = runAppleScriptString("""
        tell application "Spotify"
            if it is running then
                try
                    return spotify url of current track
                on error
                    try
                        return id of current track
                    on error
                        return ""
                    end try
                end try
            end if
        end tell
        return ""
        """)?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }

        if rawValue.hasPrefix("spotify:track:") {
            let trackID = rawValue.replacingOccurrences(of: "spotify:track:", with: "")
            return URL(string: "https://open.spotify.com/track/\(trackID)")
        }

        if let url = URL(string: rawValue), url.scheme?.hasPrefix("http") == true {
            return url
        }

        return nil
    }

    private func musicCurrentTrackURL() -> URL? {
        guard let rawValue = runAppleScriptString("""
        tell application "Music"
            if it is running then
                try
                    return address of current track
                on error
                    return ""
                end try
            end if
        end tell
        return ""
        """)?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let url = URL(string: rawValue),
              url.scheme?.hasPrefix("http") == true else {
            return nil
        }

        return url
    }

    private func browserShareURL(from browser: BrowserPlayerApp) -> URL? {
        guard let rawValue = runAppleScriptString(browser.shareURLScript)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let url = URL(string: rawValue) else {
            return nil
        }

        return url
    }

    private func currentTrackLyrics() -> String? {
        guard lastKnownPlayer == .music, PlayerApp.music.isRunning else { return nil }

        guard let rawLyrics = runAppleScriptString("""
        tell application "Music"
            if it is running then
                try
                    return lyrics of current track
                on error
                    return ""
                end try
            end if
        end tell
        return ""
        """) else {
            return nil
        }

        let preview = rawLyrics
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .prefix(2)
            .joined(separator: "  ")

        guard preview.isEmpty == false else { return nil }
        return preview
    }

    private func currentLyricsLookup() -> LyricsLookup {
        LyricsLookup(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }

    private func compactLyricsText(_ content: LyricsContent) -> String? {
        compactLyricsWindow(content)?.current
    }

    private func compactLyricsWindow(_ content: LyricsContent) -> InlineLyricsWindow? {
        if let syncedLyrics = content.syncedLyrics,
           let lyricsWindow = currentSyncedLyricWindow(from: syncedLyrics) {
            return lyricsWindow
        }

        if let plainLyrics = content.plainLyrics,
           let preview = plainLyricsWindow(plainLyrics) {
            return preview
        }

        if let syncedLyrics = content.syncedLyrics,
           let preview = plainLyricsWindow(removingLRCTimestamps(from: syncedLyrics)) {
            return preview
        }

        return nil
    }

    private func currentSyncedLyricLine(from lrc: String) -> String? {
        let entries = lrc
            .components(separatedBy: .newlines)
            .flatMap(timedLyricEntries)
            .sorted { $0.time < $1.time }

        guard entries.isEmpty == false else { return nil }

        let targetTime = max(0, playerPosition + 0.35)
        if let current = entries.last(where: { $0.time <= targetTime && $0.text.isEmpty == false }) {
            return current.text
        }

        return entries.first(where: { $0.text.isEmpty == false })?.text
    }

    private func currentSyncedLyricWindow(from lrc: String) -> InlineLyricsWindow? {
        let entries = lrc
            .components(separatedBy: .newlines)
            .flatMap(timedLyricEntries)
            .filter { $0.text.isEmpty == false }
            .sorted { $0.time < $1.time }

        guard entries.isEmpty == false else { return nil }

        let targetTime = max(0, playerPosition + 0.35)
        let currentIndex = entries.lastIndex(where: { $0.time <= targetTime }) ?? entries.startIndex
        let previousIndex = currentIndex > entries.startIndex ? entries.index(before: currentIndex) : nil
        let nextIndex = entries.index(after: currentIndex)

        return InlineLyricsWindow(
            previous: previousIndex.map { entries[$0].text },
            current: entries[currentIndex].text,
            next: nextIndex < entries.endIndex ? entries[nextIndex].text : nil
        )
    }

    private func timedLyricEntries(from line: String) -> [(time: Double, text: String)] {
        var remaining = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var timestamps: [Double] = []

        while remaining.hasPrefix("["),
              let closeIndex = remaining.firstIndex(of: "]") {
            let start = remaining.index(after: remaining.startIndex)
            let timestamp = String(remaining[start..<closeIndex])
            if let seconds = lrcTimestampSeconds(timestamp) {
                timestamps.append(seconds)
            }

            remaining = String(remaining[remaining.index(after: closeIndex)...])
        }

        let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return timestamps.map { (time: $0, text: text) }
    }

    private func lrcTimestampSeconds(_ timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(String(parts[0])) else {
            return nil
        }

        let seconds = Double(String(parts[1]).replacingOccurrences(of: ",", with: ".")) ?? 0
        return minutes * 60 + seconds
    }

    private func plainLyricsPreview(_ lyrics: String) -> String? {
        plainLyricsWindow(lyrics)?.current
    }

    private func plainLyricsWindow(_ lyrics: String) -> InlineLyricsWindow? {
        let preview = lyrics
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .prefix(3)

        guard let current = preview.first else { return nil }
        let next = preview.dropFirst().first
        return InlineLyricsWindow(previous: nil, current: current, next: next)
    }

    private func removingLRCTimestamps(from lyrics: String) -> String {
        lyrics
            .components(separatedBy: .newlines)
            .map { line in
                var remaining = line
                while remaining.trimmingCharacters(in: .whitespaces).hasPrefix("["),
                      let closeIndex = remaining.firstIndex(of: "]") {
                    remaining = String(remaining[remaining.index(after: closeIndex)...])
                }
                return remaining
            }
            .joined(separator: "\n")
    }

    private func startObservingSystemNowPlaying() {
        // Private MediaRemote control/queue APIs log sandbox permission errors on recent macOS.
    }

    private func startObservingPlayers() {
        let musicObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handlePlayerNotification(note, player: .music)
        }

        let spotifyObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handlePlayerNotification(note, player: .spotify)
        }

        observers = [musicObserver, spotifyObserver]
    }

    private func handlePlayerNotification(_ note: Notification, player: PlayerApp) {
        guard let info = note.userInfo else { return }

        let state = (info["Player State"] as? String) ?? ""
        let playing = state.localizedCaseInsensitiveContains("playing")
        let name = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        let previousTrackKey = "\(title)|\(self.artist)|\(self.album)"
        let nextTrackKey = "\(name.isEmpty ? "Not playing" : name)|\(artist)|\(album)"
        let didChangeTrack = previousTrackKey != nextTrackKey

        if name.isEmpty, applyBrowserNowPlaying(allowZeroReset: false) {
            return
        }

        lastKnownPlayer = player
        lastCommandTarget = .player(player)
        sourceName = player.displayName
        isPlaying = playing
        title = name.isEmpty ? "Not playing" : name
        self.artist = artist
        self.album = album
        if didChangeTrack, name.isEmpty == false {
            playerPosition = 0
            lastProgressUpdate = Date()
            didRefreshNearTrackEnd = false
            lastNearTrackEndRefresh = .distantPast
        }
        updateTiming(from: info)
        if didChangeTrack || artwork == nil {
            updateArtwork(from: info, player: player)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshPlaybackPosition(allowZeroReset: false)
        }
    }

    private func refreshFromRunningPlayers(allowZeroReset: Bool = false) {
        for player in PlayerApp.allCases where player.isRunning {
            if let state = readState(from: player), !state.title.isEmpty {
                let didChangeTrack = title != state.title || artist != state.artist || album != state.album
                lastKnownPlayer = player
                lastCommandTarget = .player(player)
                applyTrackState(
                    state,
                    sourceName: player.displayName,
                    allowZeroReset: allowZeroReset
                )
                if didChangeTrack || artwork == nil {
                    loadArtworkFromPlayer(player)
                }
                return
            }
        }
    }

    private func refreshFromSystemNowPlaying(
        allowZeroReset: Bool = false,
        fallbackToRunningPlayers: Bool = false,
        preferredSourceName: String? = nil
    ) {
        if fallbackToRunningPlayers {
            refreshFromRunningPlayers(allowZeroReset: allowZeroReset)
        }
    }

    private func refreshFromPreferredNowPlaying(allowZeroReset: Bool = false) {
        if applyBrowserNowPlaying(allowZeroReset: allowZeroReset) {
            return
        }

        refreshFromRunningPlayers(allowZeroReset: allowZeroReset)
    }

    @discardableResult
    private func applyBrowserNowPlaying(allowZeroReset: Bool) -> Bool {
        for browser in BrowserPlayerApp.allCases where browser.isRunning {
            guard let state = readBrowserState(from: browser) else { continue }

            applyBrowserState(state, browser: browser, allowZeroReset: allowZeroReset)
            return true
        }

        return false
    }

    private func applyBrowserState(_ state: TrackState, browser: BrowserPlayerApp, allowZeroReset: Bool) {
        lastCommandTarget = .browser(browser)
        applyTrackState(
            state,
            sourceName: browser.displayName,
            allowZeroReset: allowZeroReset
        )

        if let artworkURL = state.artworkURL {
            loadArtwork(from: artworkURL)
        } else {
            artwork = state.artwork
            lastArtworkURL = nil
        }
    }

    private func readBrowserState(from browser: BrowserPlayerApp) -> TrackState? {
        guard let result = runAppleScriptString(browser.stateScript), result.isEmpty == false else {
            return nil
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6, parts[0].isEmpty == false else { return nil }

        return TrackState(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[5].localizedCaseInsensitiveContains("playing"),
            duration: normalizedDuration(parsedScriptDouble(parts[3])),
            position: normalizedPosition(parsedScriptDouble(parts[4])),
            sourceName: browser.displayName,
            artworkURL: parts.count > 6 ? URL(string: parts[6]) : nil
        )
    }

    private func applyTrackState(_ state: TrackState, sourceName: String, allowZeroReset: Bool) {
        let didChangeTrack = title != state.title || artist != state.artist || album != state.album

        self.sourceName = sourceName
        title = state.title
        artist = state.artist
        album = state.album
        isPlaying = state.isPlaying
        duration = state.duration
        if didChangeTrack {
            lastArtworkURL = nil
            playerPosition = 0
            lastProgressUpdate = Date()
            didRefreshNearTrackEnd = false
            lastNearTrackEndRefresh = .distantPast
        }
        applyPlayerPosition(state.position, allowZeroReset: allowZeroReset || didChangeTrack)
    }

    private func readState(from player: PlayerApp) -> TrackState? {
        guard let result = runAppleScriptString(player.stateScript) else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }

        return TrackState(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[3].localizedCaseInsensitiveContains("playing"),
            duration: normalizedDuration(parsedScriptDouble(parts[4])),
            position: normalizedPosition(parsedScriptDouble(parts[5]))
        )
    }

    private func startProgressTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickPlaybackProgress()
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func tickPlaybackProgress() {
        if isPlaying {
            advanceLocalPosition()
        }
    }

    private func refreshPlaybackPosition(allowZeroReset: Bool) {
        if case let .browser(browser) = lastCommandTarget {
            if browser.isRunning, let state = readBrowserState(from: browser) {
                applyBrowserState(state, browser: browser, allowZeroReset: allowZeroReset)
            } else {
                refreshFromSystemNowPlaying(allowZeroReset: allowZeroReset, fallbackToRunningPlayers: true)
            }
            return
        }

        if lastCommandTarget == .systemMedia {
            refreshFromRunningPlayers(allowZeroReset: allowZeroReset)
            return
        }

        let player = lastKnownPlayer.isRunning ? lastKnownPlayer : PlayerApp.allCases.first(where: \.isRunning) ?? lastKnownPlayer
        guard let state = readState(from: player) else { return }

        lastKnownPlayer = player
        isPlaying = state.isPlaying
        duration = state.duration
        applyPlayerPosition(state.position, allowZeroReset: allowZeroReset)
    }

    private func advanceLocalPosition() {
        guard duration > 0 else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastProgressUpdate)
        guard elapsed > 0 else { return }

        let nextPosition = min(duration, playerPosition + elapsed)
        playerPosition = nextPosition
        lastProgressUpdate = now

        if nextPosition >= max(0, duration - 0.8),
           now.timeIntervalSince(lastNearTrackEndRefresh) > 1.0 {
            didRefreshNearTrackEnd = true
            lastNearTrackEndRefresh = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshFromPreferredNowPlaying(allowZeroReset: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.refreshFromPreferredNowPlaying(allowZeroReset: true)
            }
        }
    }

    private func applyPlayerPosition(_ position: Double, allowZeroReset: Bool = false) {
        guard duration > 0 else {
            playerPosition = max(0, position)
            lastProgressUpdate = Date()
            return
        }

        let clampedPosition = min(max(0, position), duration)

        if clampedPosition > 0 || allowZeroReset {
            playerPosition = clampedPosition
            lastProgressUpdate = Date()
            if clampedPosition < max(0, duration - 2.0) {
                didRefreshNearTrackEnd = false
                lastNearTrackEndRefresh = .distantPast
            }
        }
    }

    private func sendCommand(_ command: String, fallbackMediaKey: MediaKey) {
        if case .browser = lastCommandTarget {
            postMediaKey(fallbackMediaKey)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshFromPreferredNowPlaying(allowZeroReset: false)
            }
            return
        }

        if lastCommandTarget == .systemMedia {
            postMediaKey(fallbackMediaKey)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshFromRunningPlayers()
            }
            return
        }

        let target = lastKnownPlayer.isRunning ? lastKnownPlayer : PlayerApp.allCases.first(where: \.isRunning) ?? lastKnownPlayer
        let didSendAppleScript = runAppleScriptCommand("""
        tell application "\(target.scriptName)"
            \(command)
        end tell
        """)

        if didSendAppleScript == false {
            postMediaKey(fallbackMediaKey)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshFromRunningPlayers()
        }
    }

    private func runAppleScriptString(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = compiledAppleScript(for: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    private func runAppleScriptCommand(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = compiledAppleScript(for: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }

    private func compiledAppleScript(for source: String) -> NSAppleScript? {
        if let script = scriptCache[source] {
            return script
        }

        guard let script = NSAppleScript(source: source) else { return nil }
        scriptCache[source] = script
        return script
    }

    private func updateArtwork(from info: [AnyHashable: Any], player: PlayerApp) {
        let imageKeys = ["Artwork", "artwork", "Album Art", "Album Artwork"]
        for key in imageKeys {
            if let image = info[key] as? NSImage {
                lastArtworkURL = nil
                artwork = image
                return
            }

            if let data = info[key] as? Data, let image = NSImage(data: data) {
                lastArtworkURL = nil
                artwork = image
                return
            }
        }

        let urlKeys = ["Artwork URL", "Artwork Url", "ArtworkURL", "Album Art URL", "AlbumArtURL"]
        for key in urlKeys {
            if let url = artworkURL(from: info[key]) {
                loadArtwork(from: url)
                return
            }
        }

        loadArtworkFromPlayer(player)
    }

    private func updateTiming(from info: [AnyHashable: Any]) {
        if let totalTime = doubleValue(info["Total Time"]) {
            duration = normalizedDuration(totalTime)
        } else if let durationValue = doubleValue(info["Duration"]) {
            duration = normalizedDuration(durationValue)
        }

        if let position = doubleValue(info["Player Position"]) ?? doubleValue(info["Playback Position"]) {
            applyPlayerPosition(normalizedPosition(position), allowZeroReset: true)
        }
    }

    private func normalizedDuration(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }

        // Spotify notifications report milliseconds; Music AppleScript reports seconds.
        if value > 86_400 {
            return value / 1000
        }

        return value
    }

    private func normalizedPosition(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }

        if value > 86_400 {
            return value / 1000
        }

        return value
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return parsedScriptDouble(string)
        }

        return nil
    }

    private func parsedScriptDouble(_ string: String) -> Double {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalized) ?? 0
    }

    private func artworkURL(from value: Any?) -> URL? {
        if let url = value as? URL {
            return url
        }

        if let string = value as? String {
            return URL(string: string)
        }

        return nil
    }

    private func loadArtwork(from url: URL) {
        if lastArtworkURL == url, artwork != nil {
            return
        }
        lastArtworkURL = url

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.artwork = image
            }
        }.resume()
    }

    private func loadArtworkFromPlayer(_ player: PlayerApp) {
        guard let result = runAppleScriptString(player.artworkScript), result.isEmpty == false else {
            lastArtworkURL = nil
            artwork = nil
            return
        }

        if let url = URL(string: result), url.scheme?.hasPrefix("http") == true {
            loadArtwork(from: url)
            return
        }

        let fileURL = URL(fileURLWithPath: result)
        lastArtworkURL = nil
        if let image = NSImage(contentsOf: fileURL) {
            artwork = image
        } else {
            artwork = nil
        }
    }

    private func postMediaKey(_ key: MediaKey) {
        postMediaKey(key.rawValue, keyDown: true)
        postMediaKey(key.rawValue, keyDown: false)
    }

    private func postMediaKey(_ keyCode: Int, keyDown: Bool) {
        let keyState = keyDown ? 0xA : 0xB
        let data1 = (keyCode << 16) | (keyState << 8)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return
        }

        event.post(tap: .cghidEventTap)
    }
}

private struct LyricsLookup {
    let title: String
    let artist: String
    let album: String
    let duration: Double

    init(title: String, artist: String, album: String, duration: Double) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        self.duration = duration
    }

    var isValid: Bool {
        title.isEmpty == false && title != "Not playing"
    }

    var cacheKey: String {
        [
            normalizedCacheComponent(title),
            normalizedCacheComponent(artist),
            normalizedCacheComponent(album)
        ]
        .joined(separator: "|")
    }

    private func normalizedCacheComponent(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OutputVolumeState {
    let level: Double
    let isMuted: Bool
}

private struct LyricsContent {
    let plainLyrics: String?
    let syncedLyrics: String?

    var hasLyrics: Bool {
        plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private final class LRCLIBLyricsClient {
    private static let requestTimeout: TimeInterval = 12.0
    private static let lookupTimeout: TimeInterval = 12.0

    private let decoder = JSONDecoder()
    private let session: URLSession

    private enum LyricsEndpoint {
        case exact(URL)
        case search(URL)
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.lookupTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    func fetchLyrics(for lookup: LyricsLookup, completion: @escaping (LyricsContent?) -> Void) {
        let endpoints = lyricsEndpoints(for: lookup)
        guard endpoints.isEmpty == false else {
            completion(nil)
            return
        }

        fetchEndpointSequence(
            endpoints,
            index: 0,
            lookup: lookup,
            startedAt: Date(),
            completion: completion
        )
    }

    private func fetchEndpointSequence(
        _ endpoints: [LyricsEndpoint],
        index: Int,
        lookup: LyricsLookup,
        startedAt: Date,
        completion: @escaping (LyricsContent?) -> Void
    ) {
        let remainingLookupTime = Self.lookupTimeout - Date().timeIntervalSince(startedAt)
        guard endpoints.indices.contains(index),
              remainingLookupTime > 0.35 else {
            completion(nil)
            return
        }

        fetchEndpoint(
            endpoints[index],
            lookup: lookup,
            timeout: min(Self.requestTimeout, remainingLookupTime)
        ) { [weak self] content in
            guard let self else {
                completion(nil)
                return
            }

            if let content {
                completion(content)
                return
            }

            self.fetchEndpointSequence(
                endpoints,
                index: index + 1,
                lookup: lookup,
                startedAt: startedAt,
                completion: completion
            )
        }
    }

    private func fetchEndpoint(
        _ endpoint: LyricsEndpoint,
        lookup: LyricsLookup,
        timeout: TimeInterval,
        completion: @escaping (LyricsContent?) -> Void
    ) {
        let url: URL
        switch endpoint {
        case let .exact(endpointURL), let .search(endpointURL):
            url = endpointURL
        }

        dataTask(url: url, timeout: timeout) { [weak self] data in
            guard let self, let data else {
                completion(nil)
                return
            }

            let lyricsContent: LyricsContent?
            switch endpoint {
            case .exact:
                let response = try? self.decoder.decode(LRCLIBLyricsResponse.self, from: data)
                lyricsContent = response?.lyricsContent
            case .search:
                let results = (try? self.decoder.decode([LRCLIBLyricsResponse].self, from: data)) ?? []
                let bestResult = results
                    .filter { $0.lyricsContent?.hasLyrics == true }
                    .max { self.matchScore($0, lookup: lookup) < self.matchScore($1, lookup: lookup) }

                if let bestResult,
                   self.matchScore(bestResult, lookup: lookup) > 0 {
                    lyricsContent = bestResult.lyricsContent
                } else {
                    lyricsContent = nil
                }
            }

            guard let lyricsContent else {
                completion(nil)
                return
            }

            completion(lyricsContent)
        }
    }

    private func lyricsEndpoints(for lookup: LyricsLookup) -> [LyricsEndpoint] {
        let searchEndpoints = searchURLs(for: lookup)
            .prefix(4)
            .map { LyricsEndpoint.search($0) }

        let exactEndpoints = exactLookupCandidates(for: lookup)
            .compactMap { lyricsURL(path: "/api/get", lookup: $0) }
            .prefix(2)
            .map { LyricsEndpoint.exact($0) }

        return searchEndpoints + exactEndpoints
    }

    private func lyricsURL(path: String, lookup: LyricsLookup) -> URL? {
        var queryItems = [URLQueryItem(name: "track_name", value: lookup.title)]
        if lookup.artist.isEmpty == false {
            queryItems.append(URLQueryItem(name: "artist_name", value: lookup.artist))
        }
        if path == "/api/get", lookup.album.isEmpty == false {
            queryItems.append(URLQueryItem(name: "album_name", value: lookup.album))
        }
        if path == "/api/get", lookup.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: "\(Int(lookup.duration.rounded()))"))
        }

        return lyricsURL(path: path, queryItems: queryItems)
    }

    private func lyricsURL(path: String, queryName: String, query: String) -> URL? {
        lyricsURL(path: path, queryItems: [URLQueryItem(name: queryName, value: query)])
    }

    private func lyricsURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private func exactLookupCandidates(for lookup: LyricsLookup) -> [LyricsLookup] {
        uniquedLookups([
            lookup,
            cleanedLookup(from: lookup, keepAlbum: false),
            cleanedLookup(from: lookup, keepAlbum: true)
        ])
    }

    private func searchURLs(for lookup: LyricsLookup) -> [URL] {
        let cleaned = cleanedLookup(from: lookup, keepAlbum: false)
        let queryValues = [
            joinedQuery(artist: lookup.artist, title: lookup.title),
            joinedQuery(artist: cleaned.artist, title: cleaned.title),
            lookup.title,
            cleaned.title
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }

        let structuredQueries = [
            lyricsURL(path: "/api/search", lookup: lookup),
            lyricsURL(path: "/api/search", lookup: cleaned)
        ].compactMap { $0 }

        let broadQueries = queryValues.compactMap { query in
            lyricsURL(path: "/api/search", queryName: "query", query: query)
        }

        let queries = structuredQueries + broadQueries

        var seen = Set<String>()
        return queries.filter { url in
            let key = url.absoluteString
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func cleanedLookup(from lookup: LyricsLookup, keepAlbum: Bool) -> LyricsLookup {
        LyricsLookup(
            title: cleanedSongComponent(lookup.title),
            artist: cleanedArtistName(lookup.artist),
            album: keepAlbum ? cleanedSongComponent(lookup.album) : "",
            duration: lookup.duration
        )
    }

    private func uniquedLookups(_ lookups: [LyricsLookup]) -> [LyricsLookup] {
        var seen = Set<String>()
        return lookups.filter { lookup in
            guard lookup.isValid, seen.contains(lookup.cacheKey) == false else { return false }
            seen.insert(lookup.cacheKey)
            return true
        }
    }

    private func joinedQuery(artist: String, title: String) -> String {
        [artist, title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private func cleanedArtistName(_ value: String) -> String {
        let separators = [
            " feat. ",
            " feat ",
            " ft. ",
            " ft ",
            " featuring ",
            " with ",
            " & ",
            ",",
            " x ",
            " vs. ",
            " vs "
        ]
        return shortened(value, at: separators)
    }

    private func cleanedSongComponent(_ value: String) -> String {
        shortened(
            value,
            at: [
                " (",
                " [",
                " {",
                " - Remaster",
                " - remaster",
                " - Remastered",
                " - remastered",
                " - Live",
                " - live",
                " - Radio Edit",
                " - radio edit",
                " - Edit",
                " - edit",
                " - Remix",
                " - remix",
                " - Version",
                " - version",
                " feat. ",
                " feat ",
                " ft. ",
                " ft ",
                " featuring "
            ]
        )
    }

    private func shortened(_ value: String, at markers: [String]) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in markers {
            if let range = cleaned.range(of: marker, options: [.caseInsensitive]) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dataTask(url: URL, timeout: TimeInterval, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Monotch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Monotch/1.0", forHTTPHeaderField: "Lrclib-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, _ in
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                completion(nil)
                return
            }

            completion(data)
        }.resume()
    }

    private func matchScore(_ response: LRCLIBLyricsResponse, lookup: LyricsLookup) -> Int {
        var score = 0
        let cleaned = cleanedLookup(from: lookup, keepAlbum: false)
        let titleCandidates = [lookup.title, cleaned.title]
        let artistCandidates = [lookup.artist, cleaned.artist]
        let albumCandidates = [lookup.album, cleanedSongComponent(lookup.album)]

        score += bestTextScore(response.trackName, candidates: titleCandidates, exact: 12, partial: 5)
        score += bestTextScore(response.artistName, candidates: artistCandidates, exact: 10, partial: 4)
        score += bestTextScore(response.albumName, candidates: albumCandidates, exact: 4, partial: 1)

        if lookup.duration > 0, let duration = response.duration {
            let difference = abs(duration - lookup.duration)
            if difference < 2 {
                score += 4
            } else if difference < 6 {
                score += 2
            }
        }

        if response.syncedLyrics?.isEmpty == false {
            score += 2
        }

        return score
    }

    private func bestTextScore(_ value: String?, candidates: [String], exact: Int, partial: Int) -> Int {
        let response = normalized(value)
        guard response.isEmpty == false else { return 0 }

        return candidates.reduce(0) { bestScore, candidate in
            let normalizedCandidate = normalized(candidate)
            guard normalizedCandidate.isEmpty == false else { return bestScore }

            if response == normalizedCandidate {
                return max(bestScore, exact)
            }

            if response.contains(normalizedCandidate) || normalizedCandidate.contains(response) {
                return max(bestScore, partial)
            }

            return bestScore
        }
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct LRCLIBLyricsResponse: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?

        var lyricsContent: LyricsContent? {
            let content = LyricsContent(plainLyrics: plainLyrics, syncedLyrics: syncedLyrics)
            return content.hasLyrics ? content : nil
        }
    }
}

enum MediaKey: Int {
    case playPause = 16
    case next = 17
    case previous = 18
}

struct TrackState {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
    var sourceName: String? = nil
    var artwork: NSImage? = nil
    var artworkURL: URL? = nil
}

private enum PlaybackCommandTarget: Equatable {
    case systemMedia
    case browser(BrowserPlayerApp)
    case player(PlayerApp)
}

private enum BrowserSystemPlayerApp {
    case firefox

    var displayName: String {
        switch self {
        case .firefox: return "Firefox"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .firefox: return "org.mozilla.firefox"
        }
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }
}

private enum BrowserPlayerApp: CaseIterable {
    case safari
    case chrome
    case edge
    case brave
    case arc

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        }
    }

    var scriptName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .arc: return "company.thebrowser.Browser"
        }
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    var stateScript: String {
        switch self {
        case .safari:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set playbackInfo to do JavaScript \(Self.appleScriptString(Self.playbackJavaScript)) in browserTab
                                if playbackInfo is not "" then return playbackInfo
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
        default:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set playbackInfo to execute javascript \(Self.appleScriptString(Self.playbackJavaScript)) in browserTab
                                if playbackInfo is not "" then return playbackInfo
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
        }
    }

    func seekScript(position: Double) -> String {
        let javaScript = """
        (() => { const media = Array.from(document.querySelectorAll('video,audio')).find(m => !m.paused && !m.ended && m.readyState > 0); if (!media) return false; media.currentTime = \(position); return true; })()
        """

        switch self {
        case .safari:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set didSeek to do JavaScript \(Self.appleScriptString(javaScript)) in browserTab
                                if didSeek is true then return true
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return false
            """
        default:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set didSeek to execute javascript \(Self.appleScriptString(javaScript)) in browserTab
                                if didSeek is true then return true
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return false
            """
        }
    }

    var shareURLScript: String {
        let javaScript = """
        (() => { const media = Array.from(document.querySelectorAll('video,audio')).find(m => !m.paused && !m.ended && m.readyState > 0); return media ? location.href : ''; })()
        """

        switch self {
        case .safari:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set shareURL to do JavaScript \(Self.appleScriptString(javaScript)) in browserTab
                                if shareURL is not "" then return shareURL
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
        default:
            return """
            tell application "\(scriptName)"
                if it is running then
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            try
                                set shareURL to execute javascript \(Self.appleScriptString(javaScript)) in browserTab
                                if shareURL is not "" then return shareURL
                            end try
                        end repeat
                    end repeat
                end if
            end tell
            return ""
            """
        }
    }

    private static let playbackJavaScript = """
    (() => { const media = Array.from(document.querySelectorAll('video,audio')).find(m => !m.paused && !m.ended && m.readyState > 0); if (!media) return ''; const metadata = navigator.mediaSession && navigator.mediaSession.metadata; const clean = value => String(value || '').replaceAll('|', ' ').replace(/[\\r\\n]+/g, ' ').trim(); const title = clean((metadata && metadata.title) || document.title); const artist = clean((metadata && metadata.artist) || location.hostname); const album = clean((metadata && metadata.album) || ''); const duration = Number.isFinite(media.duration) ? media.duration : 0; const position = Number.isFinite(media.currentTime) ? media.currentTime : 0; const artwork = metadata && metadata.artwork && metadata.artwork.length ? metadata.artwork[metadata.artwork.length - 1].src : ''; return [title, artist, album, duration, position, 'playing', artwork].join('|||'); })()
    """

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        return "\"\(escaped)\""
    }
}

private enum PlayerApp: CaseIterable {
    case music
    case spotify

    var displayName: String {
        switch self {
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var scriptName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    var stateScript: String {
        """
        tell application "\(scriptName)"
            if it is running then
                set trackName to ""
                set trackArtist to ""
                set trackAlbum to ""
                set trackDuration to 0
                set trackPosition to 0
                set playerState to player state as string
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set trackPosition to player position
                end try
                return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & playerState & "|||" & trackDuration & "|||" & trackPosition
            end if
        end tell
        """
    }

    var artworkScript: String {
        switch self {
        case .music:
            return """
            tell application "Music"
                if it is running then
                    try
                        set artworkFile to "/private/tmp/MONOTCH-current-artwork.jpg"
                        set rawArtwork to data of artwork 1 of current track
                        set fileReference to open for access POSIX file artworkFile with write permission
                        set eof of fileReference to 0
                        write rawArtwork to fileReference
                        close access fileReference
                        return artworkFile
                    on error
                        try
                            close access POSIX file artworkFile
                        end try
                        return ""
                    end try
                end if
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                if it is running then
                    try
                        return artwork url of current track
                    on error
                        return ""
                    end try
                end if
            end tell
            """
        }
    }
}

private final class SpotifyAccessibility {
    private let bundleIdentifier = "com.spotify.client"

    func addCurrentTrackToLikedSongs() -> String {
        guard let pid = spotifyPID() else {
            return "Spotify is not running"
        }

        guard ensureAccessibilityAccess() else {
            return "Allow Accessibility to like in Spotify"
        }

        let app = AXUIElementCreateApplication(pid)
        let buttons = spotifyActionButtons(in: app)

        if let likeButton = buttons.first(where: { isAddToLikedSongsLabel($0.label) })?.element {
            let result = AXUIElementPerformAction(likeButton, kAXPressAction as CFString)
            return result == .success ? "Added to liked songs" : "Spotify like unavailable"
        }

        if buttons.contains(where: { isAlreadyLikedSongsLabel($0.label) }) {
            return "Already liked"
        }

        return "Spotify like unavailable"
    }

    func loadQueue(completion: @escaping ([String]) -> Void) {
        guard let pid = spotifyPID() else {
            completion(["Spotify is not running"])
            return
        }

        guard ensureAccessibilityAccess() else {
            completion(["Allow Accessibility to read Spotify queue"])
            return
        }

        let app = AXUIElementCreateApplication(pid)
        openQueuePanel(in: app)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            completion(self.queueTitles(in: app))
        }
    }

    private func spotifyPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleIdentifier }?
            .processIdentifier
    }

    private func ensureAccessibilityAccess() -> Bool {
        guard AXIsProcessTrusted() == false else { return true }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        return false
    }

    private func openQueuePanel(in app: AXUIElement) {
        for (button, label) in spotifyActionButtons(in: app) {
            if label.contains("queue") {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                return
            }
        }
    }

    private func spotifyActionButtons(in app: AXUIElement) -> [(element: AXUIElement, label: String)] {
        var buttons: [AXUIElement] = []
        findElements(in: app, role: kAXButtonRole as String, results: &buttons)

        return buttons.compactMap { button in
            let label = buttonLabel(button)
            return label.isEmpty ? nil : (button, label)
        }
    }

    private func buttonLabel(_ button: AXUIElement) -> String {
        [
            stringAttribute(button, kAXDescriptionAttribute),
            stringAttribute(button, kAXTitleAttribute),
            stringAttribute(button, kAXValueAttribute),
            stringAttribute(button, kAXRoleDescriptionAttribute)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
    }

    private func isAddToLikedSongsLabel(_ label: String) -> Bool {
        guard label.contains("remove") == false,
              label.contains("unlike") == false,
              label.contains("saved") == false,
              label.contains("added") == false,
              label.contains("kaldir") == false,
              label.contains("kaydedildi") == false,
              label.contains("eklendi") == false else {
            return false
        }

        let words = Set(label.split(separator: " ").map(String.init))
        let hasLibraryTarget = label.contains("library")
            || label.contains("liked")
            || label.contains("kitaplik")
            || label.contains("begen")
        let hasSaveIntent = words.contains("save")
            || words.contains("add")
            || words.contains("kaydet")
            || words.contains("ekle")
        let hasLikeIntent = words.contains("like")
            || label.contains("like this song")
            || label.contains("sarkiyi begen")

        return label.contains("save to your library")
            || label.contains("add to your library")
            || label.contains("save to liked songs")
            || label.contains("add to liked songs")
            || label.contains("begenilen sarkilar")
            || (hasLibraryTarget && hasSaveIntent)
            || hasLikeIntent
    }

    private func isAlreadyLikedSongsLabel(_ label: String) -> Bool {
        (label.contains("remove") && (label.contains("library") || label.contains("liked songs")))
            || label.contains("saved to your library")
            || label.contains("added to liked songs")
            || label.contains("already liked")
            || (label.contains("kaldir") && (label.contains("kitaplik") || label.contains("begen")))
            || label.contains("kaydedildi")
            || label.contains("eklendi")
            || label == "saved"
            || label == "saved button"
    }

    private func queueTitles(in app: AXUIElement) -> [String] {
        var cells: [AXUIElement] = []
        findElements(in: app, role: kAXCellRole as String, results: &cells)

        let titles = cells.compactMap { queueTitle(from: $0) }
        return Array(titles.uniquedPreservingOrder().prefix(8))
    }

    private func queueTitle(from element: AXUIElement) -> String? {
        let candidates = [
            stringAttribute(element, kAXTitleAttribute),
            stringAttribute(element, kAXDescriptionAttribute),
            stringAttribute(element, kAXValueAttribute),
            childStaticText(in: element)
        ]

        return candidates
            .compactMap { $0 }
            .compactMap(normalizedQueueTitle)
            .first
    }

    private func findElements(
        in element: AXUIElement,
        role: String,
        depth: Int = 0,
        results: inout [AXUIElement]
    ) {
        guard depth < 14, results.count < 220 else { return }

        if stringAttribute(element, kAXRoleAttribute) == role {
            results.append(element)
        }

        guard let children = attributeValue(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return
        }

        for child in children {
            findElements(in: child, role: role, depth: depth + 1, results: &results)
        }
    }

    private func childStaticText(in element: AXUIElement) -> String? {
        guard let children = attributeValue(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        let parts = children.compactMap { child -> String? in
            if stringAttribute(child, kAXRoleAttribute) == (kAXStaticTextRole as String) {
                return stringAttribute(child, kAXValueAttribute)
                    ?? stringAttribute(child, kAXTitleAttribute)
            }

            return childStaticText(in: child)
        }

        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func normalizedQueueTitle(_ value: String) -> String? {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 1 else { return nil }

        let lowercased = trimmed.lowercased()
        let ignoredLabels = [
            "queue",
            "now playing",
            "next in queue",
            "open queue",
            "more",
            "play",
            "pause"
        ]

        guard ignoredLabels.contains(lowercased) == false else { return nil }
        guard lowercased.contains("advertisement") == false else { return nil }

        return trimmed
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        if let string = attributeValue(element, attribute) as? String {
            return string
        }

        if let number = attributeValue(element, attribute) as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private func attributeValue(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { value in
            let key = value.lowercased()
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }
}
