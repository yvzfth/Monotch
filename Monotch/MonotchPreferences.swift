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
    static let appLanguage = "appLanguage"
    static let previousTabShortcut = "previousTabShortcut"
    static let nextTabShortcut = "nextTabShortcut"
    static let toggleLyricsShortcut = "toggleLyricsShortcut"
    static let mediaTabHintSeen = "mediaTabHintSeen"
    static let clipboardTabHintSeen = "clipboardTabHintSeen"
    static let systemTabHintSeen = "systemTabHintSeen"
    static let cameraTabHintSeen = "cameraTabHintSeen"
}

enum MonotchTabItem: String, CaseIterable, Identifiable {
    case multimedia
    case clipboard
    case system
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multimedia: return String(localized: "Media Player", comment: "A menu item that opens the media player.")
        case .clipboard: return String(localized: "Clipboard", comment: "A command that opens the clipboard.")
        case .system: return String(localized: "System", comment: "A button that opens the system settings.")
        case .camera: return String(localized: "Camera", comment: "A button that opens the camera app.")
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
        case .history: return String(localized: "Clipboard", comment: "The clipboard history card title.")
        case .files: return String(localized: "Files", comment: "The files card title.")
        case .downloads: return String(localized: "Shelf", comment: "The shelf folder card title.")
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
        case .cpu: return String(localized: "CPU", comment: "The CPU stat card title.")
        case .ram: return String(localized: "RAM", comment: "The RAM stat card title.")
        case .storage: return String(localized: "Storage", comment: "The storage stat card title.")
        case .fans: return String(localized: "Fans", comment: "The fans control card title.")
        case .sensors: return String(localized: "Sensors", comment: "The sensors card title.")
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

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case tr
    case de
    case fr
    case es
    case zhHans = "zh-Hans"
    case hi
    case ru
    case ar
    case ko
    case ja
    case fa
    case el
    case uk

    var id: String { rawValue }

    // Native names are shown as-is (not translated) except "System Default",
    // which follows the app's current language via String(localized:).
    var title: String {
        switch self {
        case .system: return String(localized: "System Default", comment: "The option to follow the Mac's system language.")
        case .en: return "English"
        case .tr: return "Türkçe"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .zhHans: return "中文（简体）"
        case .hi: return "हिन्दी"
        case .ru: return "Русский"
        case .ar: return "العربية"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .fa: return "فارسی"
        case .el: return "Ελληνικά"
        case .uk: return "Українська"
        }
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
        case .leftArrow: return String(localized: "Left Arrow", comment: "The left arrow key.")
        case .rightArrow: return String(localized: "Right Arrow", comment: "The right arrow key.")
        case .l: return "L"
        case .p: return "P"
        case .k: return "K"
        case .none: return String(localized: "Off", comment: "No key assigned to this shortcut.")
        }
    }

    var shortTitle: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .l: return "L"
        case .p: return "P"
        case .k: return "K"
        case .none: return String(localized: "Off", comment: "No key assigned to this shortcut.")
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
