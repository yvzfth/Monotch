import AppKit
import Darwin
import Foundation

final class MediaRemoteClient {
    static let shared = MediaRemoteClient()

    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (NSDictionary?) -> Void) -> Void
    private typealias RegisterNotificationsFunction = @convention(c) (DispatchQueue) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getNowPlayingInfo: GetNowPlayingInfoFunction?
    private let registerNotifications: RegisterNotificationsFunction?
    private var notificationObservers: [NSObjectProtocol] = []
    private var didRegisterNotifications = false
    private var onChange: (() -> Void)?
    private let keyLookup: [String: String]
    private let notificationNames: [String]

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)

        getNowPlayingInfo = MediaRemoteClient.loadSymbol(
            "MRMediaRemoteGetNowPlayingInfo",
            from: handle,
            as: GetNowPlayingInfoFunction.self
        )
        registerNotifications = MediaRemoteClient.loadSymbol(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            from: handle,
            as: RegisterNotificationsFunction.self
        )
        keyLookup = Self.makeKeyLookup(from: handle)
        notificationNames = Self.makeNotificationNames(from: handle)
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }

        if let handle {
            dlclose(handle)
        }
    }

    var isAvailable: Bool {
        getNowPlayingInfo != nil
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        self.onChange = onChange

        if didRegisterNotifications == false {
            registerNotifications?(.main)
            didRegisterNotifications = true
        }

        if notificationObservers.isEmpty {
            for name in notificationNames {
                let notificationName = Notification.Name(name)
                let localObserver = NotificationCenter.default.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.onChange?()
                }
                let distributedObserver = DistributedNotificationCenter.default().addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.onChange?()
                }
                notificationObservers.append(localObserver)
                notificationObservers.append(distributedObserver)
            }
        }
    }

    func fetchNowPlaying(completion: @escaping (TrackState?) -> Void) {
        guard let getNowPlayingInfo else {
            completion(nil)
            return
        }

        getNowPlayingInfo(.main) { [weak self] info in
            completion(self?.trackState(from: info))
        }
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func makeKeyLookup(from handle: UnsafeMutableRawPointer?) -> [String: String] {
        let names = [
            "kMRMediaRemoteNowPlayingInfoTitle",
            "kMRMediaRemoteNowPlayingInfoArtist",
            "kMRMediaRemoteNowPlayingInfoAlbum",
            "kMRMediaRemoteNowPlayingInfoDuration",
            "kMRMediaRemoteNowPlayingInfoElapsedTime",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            "kMRMediaRemoteNowPlayingInfoArtworkURL",
            "kMRMediaRemoteNowPlayingInfoApplicationDisplayName",
            "kMRMediaRemoteNowPlayingInfoClientDisplayName",
            "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
        ]

        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            guard let value = stringConstant(name, from: handle) else { return nil }
            return (name, value)
        })
    }

    private static func makeNotificationNames(from handle: UnsafeMutableRawPointer?) -> [String] {
        let symbolNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]
        let resolved = symbolNames.compactMap { stringConstant($0, from: handle) }
        let fallback = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]

        return Array(Set(resolved + fallback))
    }

    private static func stringConstant(_ name: String, from handle: UnsafeMutableRawPointer?) -> String? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        let pointer = symbol.assumingMemoryBound(to: CFString?.self)
        return pointer.pointee as String?
    }

    private func trackState(from info: NSDictionary?) -> TrackState? {
        guard let info else { return nil }

        let title = stringValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoTitle",
            "Title",
            "title"
        ]), in: info)
        guard title.isEmpty == false else { return nil }

        let duration = Self.normalizedDuration(doubleValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoDuration",
            "Duration",
            "duration"
        ]), in: info))
        let position = Self.normalizedPosition(doubleValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoElapsedTime",
            "ElapsedTime",
            "elapsedTime"
        ]), in: info))
        let playbackRate = doubleValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            "PlaybackRate",
            "playbackRate"
        ]), in: info)
        let artwork = imageValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            "ArtworkData",
            "artworkData"
        ]), in: info)
        let artworkURL = urlValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoArtworkURL",
            "ArtworkURL",
            "artworkURL"
        ]), in: info)
        let sourceName = stringValue(for: keys([
            "kMRMediaRemoteNowPlayingInfoApplicationDisplayName",
            "kMRMediaRemoteNowPlayingInfoClientDisplayName",
            "ApplicationDisplayName",
            "ClientDisplayName"
        ]), in: info)

        return TrackState(
            title: title,
            artist: stringValue(for: keys([
                "kMRMediaRemoteNowPlayingInfoArtist",
                "Artist",
                "artist"
            ]), in: info),
            album: stringValue(for: keys([
                "kMRMediaRemoteNowPlayingInfoAlbum",
                "Album",
                "album"
            ]), in: info),
            isPlaying: playbackRate > 0,
            duration: duration,
            position: position,
            sourceName: sourceName.isEmpty ? "System" : sourceName,
            artwork: artwork,
            artworkURL: artworkURL
        )
    }

    private func keys(_ names: [String]) -> [String] {
        names.flatMap { name -> [String] in
            if let resolved = keyLookup[name] {
                return [resolved, name]
            }

            return [name]
        }
    }

    private func stringValue(for keys: [String], in info: NSDictionary) -> String {
        for key in keys {
            if let value = info[key] as? String {
                return value
            }
        }

        return ""
    }

    private func doubleValue(for keys: [String], in info: NSDictionary) -> Double {
        for key in keys {
            if let value = info[key] as? Double {
                return value
            }

            if let value = info[key] as? NSNumber {
                return value.doubleValue
            }

            if let value = info[key] as? String, let double = Double(value) {
                return double
            }
        }

        return 0
    }

    private func imageValue(for keys: [String], in info: NSDictionary) -> NSImage? {
        for key in keys {
            if let image = info[key] as? NSImage {
                return image
            }

            if let data = info[key] as? Data, let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    private func urlValue(for keys: [String], in info: NSDictionary) -> URL? {
        for key in keys {
            if let url = info[key] as? URL {
                return url
            }

            if let string = info[key] as? String, let url = URL(string: string) {
                return url
            }
        }

        return nil
    }

    private static func normalizedDuration(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value > 86_400 ? value / 1000 : value
    }

    private static func normalizedPosition(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return value > 86_400 ? value / 1000 : value
    }
}
