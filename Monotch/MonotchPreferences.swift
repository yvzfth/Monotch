import AppKit
import SwiftUI

enum MonotchSettingsKey {
    static let showMediaTab = "showMediaTab"
    static let showClipboardTab = "showClipboardTab"
    static let showSystemTab = "showSystemTab"
    static let showCameraTab = "showCameraTab"
    static let tabOrder = "monotchTabOrder"
    static let clipboardCardOrder = "monotchClipboardCardOrder"
    static let showClipboardHistoryCard = "showClipboardHistoryCard"
    static let showClipboardFilesCard = "showClipboardFilesCard"
    static let showClipboardDownloadsCard = "showClipboardDownloadsCard"
    static let systemCardOrder = "monotchSystemCardOrder"
    static let showSystemCPUCard = "showSystemCPUCard"
    static let showSystemRAMCard = "showSystemRAMCard"
    static let showSystemStorageCard = "showSystemStorageCard"
    static let showSystemFansCard = "showSystemFansCard"
    static let showSystemSensorsCard = "showSystemSensorsCard"
    static let openOnHover = "openOnHover"
    static let previousTabShortcut = "previousTabShortcut"
    static let nextTabShortcut = "nextTabShortcut"
    static let toggleLyricsShortcut = "toggleLyricsShortcut"
}

enum MonotchTabItem: String, CaseIterable, Identifiable {
    case multimedia
    case clipboard
    case system
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multimedia: return "Media Player"
        case .clipboard: return "Clipboard"
        case .system: return "System"
        case .camera: return "Camera"
        }
    }

    var page: WidgetPage {
        switch self {
        case .multimedia: return .multimedia
        case .clipboard: return .clipboard
        case .system: return .system
        case .camera: return .camera
        }
    }

    static var defaultOrder: [MonotchTabItem] { [.multimedia, .clipboard, .system, .camera] }
    static var defaultOrderRawValue: String { defaultOrder.map(\.rawValue).joined(separator: ",") }

    static func ordered(from rawValue: String) -> [MonotchTabItem] {
        let saved = rawValue
            .split(separator: ",")
            .compactMap { MonotchTabItem(rawValue: String($0)) }
        let missing = defaultOrder.filter { saved.contains($0) == false }
        let ordered = saved + missing
        return ordered.isEmpty ? defaultOrder : ordered
    }
}


enum MonotchClipboardCard: String, CaseIterable, Identifiable {
    case history
    case files
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "Clipboard"
        case .files: return "Files"
        case .downloads: return "Downloads"
        }
    }

    static var defaultOrder: [MonotchClipboardCard] { [.history, .files, .downloads] }
    static var defaultOrderRawValue: String { defaultOrder.map(\.rawValue).joined(separator: ",") }

    static func ordered(from rawValue: String) -> [MonotchClipboardCard] {
        let saved = rawValue
            .split(separator: ",")
            .compactMap { MonotchClipboardCard(rawValue: String($0)) }
        let missing = defaultOrder.filter { saved.contains($0) == false }
        let ordered = saved + missing
        return ordered.isEmpty ? defaultOrder : ordered
    }
}

enum MonotchSystemCard: String, CaseIterable, Identifiable {
    case cpu
    case ram
    case storage
    case fans
    case sensors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .storage: return "Storage"
        case .fans: return "Fans"
        case .sensors: return "Sensors"
        }
    }

    static var defaultOrder: [MonotchSystemCard] { [.cpu, .ram, .storage, .fans, .sensors] }
    static var defaultOrderRawValue: String { defaultOrder.map(\.rawValue).joined(separator: ",") }

    static func ordered(from rawValue: String) -> [MonotchSystemCard] {
        let saved = rawValue
            .split(separator: ",")
            .compactMap { MonotchSystemCard(rawValue: String($0)) }
        let missing = defaultOrder.filter { saved.contains($0) == false }
        let ordered = saved + missing
        return ordered.isEmpty ? defaultOrder : ordered
    }
}

enum MonotchShortcutKey: String, CaseIterable, Identifiable {
    case leftArrow
    case rightArrow
    case l
    case p
    case k
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftArrow: return "Left Arrow"
        case .rightArrow: return "Right Arrow"
        case .l: return "L"
        case .p: return "P"
        case .k: return "K"
        case .none: return "Off"
        }
    }

    var shortTitle: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .l: return "L"
        case .p: return "P"
        case .k: return "K"
        case .none: return "Off"
        }
    }

    var keyCode: UInt16? {
        switch self {
        case .leftArrow: return 123
        case .rightArrow: return 124
        case .l: return 37
        case .p: return 35
        case .k: return 40
        case .none: return nil
        }
    }

    static func matches(_ rawValue: String, event: NSEvent) -> Bool {
        guard let keyCode = MonotchShortcutKey(rawValue: rawValue)?.keyCode else { return false }
        return event.keyCode == keyCode
    }

    static func shortTitle(for rawValue: String) -> String {
        MonotchShortcutKey(rawValue: rawValue)?.shortTitle ?? rawValue
    }
}
