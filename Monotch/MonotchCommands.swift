import AppKit
import SwiftUI

struct MonotchCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("Choose Downloads Tray Folder...") {
                MonotchCommandCenter.chooseFolderShelfLocation()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Open Downloads Tray Folder") {
                MonotchCommandCenter.openFolderShelfLocation()
            }

            Button("Refresh Downloads Tray") {
                MonotchCommandCenter.refreshFolderShelf()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("Reset Tray Folder to Downloads") {
                MonotchCommandCenter.resetFolderShelfLocation()
            }
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Copy Latest Text") {
                MonotchCommandCenter.copyLatestText()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Copy Latest Image") {
                MonotchCommandCenter.copyLatestImage()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Copy Latest File") {
                MonotchCommandCenter.copyLatestFile()
            }
            .keyboardShortcut("c", modifiers: [.command, .control])

            Divider()

            Button("Clear Clipboard History") {
                MonotchCommandCenter.clearClipboardHistory()
            }

            Button("Clear Camera Roll") {
                MonotchCommandCenter.clearCameraRoll()
            }
        }

        CommandMenu("Selection") {
            Button("Media Player") {
                MonotchCommandCenter.showPage(.multimedia)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Clipboard") {
                MonotchCommandCenter.showPage(.clipboard)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("System") {
                MonotchCommandCenter.showPage(.system)
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Camera") {
                MonotchCommandCenter.showPage(.camera)
            }
            .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Previous Tab") {
                MonotchCommandCenter.previousTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Button("Next Tab") {
                MonotchCommandCenter.nextTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
        }

        CommandGroup(after: .toolbar) {
            Divider()

            Button("Show Monotch") {
                MonotchCommandCenter.showNotch()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Collapse to Nub") {
                MonotchCommandCenter.collapseNotch()
            }

            Divider()

            Button("Previous Tab") {
                MonotchCommandCenter.previousTab()
            }

            Button("Next Tab") {
                MonotchCommandCenter.nextTab()
            }
        }

        CommandGroup(after: .windowArrangement) {
            Divider()

            Button("Show Monotch Window") {
                MonotchCommandCenter.showNotch()
            }

            Button("Hide Monotch Window") {
                MonotchCommandCenter.hideNotch()
            }

            Button("Open Settings Window") {
                openSettings()
            }
        }

        CommandGroup(replacing: .help) {
            Button("Monotch Help") {
                openWindow(id: "monotch-help")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Troubleshooting") {
                openWindow(id: "monotch-help")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Licensing & Credits") {
                openWindow(id: "monotch-help")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Show Shortcuts") {
                openSettings()
            }
        }
    }


}

enum MonotchCommandCenter {
    static func showNotch() {
        NotchWindowController.shared.showExpanded()
    }

    static func collapseNotch() {
        NotchUIState.shared.isExpanded = false
        NotchWindowController.shared.showCollapsed()
    }

    static func hideNotch() {
        NotchUIState.shared.isExpanded = false
        NotchWindowController.shared.hideCompletely()
    }

    static func showPage(_ page: WidgetPage) {
        let pages = enabledPages()
        guard let index = pages.firstIndex(of: page) else {
            NSSound.beep()
            return
        }

        NotchWindowController.shared.showExpanded()
        NotchUIState.shared.requestPage(rawValue: index)
    }

    static func previousTab() {
        NotchWindowController.shared.showExpanded()
        NotchUIState.shared.requestRelativePage(direction: -1)
    }

    static func nextTab() {
        NotchWindowController.shared.showExpanded()
        NotchUIState.shared.requestRelativePage(direction: 1)
    }

    private static func enabledPages() -> [WidgetPage] {
        let defaults = UserDefaults.standard
        let order = defaults.string(forKey: MonotchSettingsKey.tabOrder) ?? MonotchTabItem.defaultOrderRawValue
        let pages = MonotchTabItem.ordered(from: order)
            .map(\.page)
            .filter { page in
                switch page {
                case .multimedia:
                    return defaults.object(forKey: MonotchSettingsKey.showMediaTab) as? Bool ?? true
                case .clipboard:
                    return defaults.object(forKey: MonotchSettingsKey.showClipboardTab) as? Bool ?? true
                case .system:
                    return defaults.object(forKey: MonotchSettingsKey.showSystemTab) as? Bool ?? true
                case .camera:
                    return defaults.object(forKey: MonotchSettingsKey.showCameraTab) as? Bool ?? true
                }
            }

        return pages.isEmpty ? [.multimedia] : pages
    }

    static func chooseFolderShelfLocation() {
        ClipboardManager.shared.chooseFolderShelfLocation()
    }

    static func openFolderShelfLocation() {
        NSWorkspace.shared.open(ClipboardManager.shared.folderShelfURL)
    }

    static func refreshFolderShelf() {
        ClipboardManager.shared.refreshFolderShelf()
    }

    static func resetFolderShelfLocation() {
        ClipboardManager.shared.resetFolderShelfLocation()
    }

    static func copyLatestText() {
        if ClipboardManager.shared.copyLatestTextToPasteboard() == false {
            NSSound.beep()
        }
    }

    static func copyLatestImage() {
        if ClipboardManager.shared.copyLatestImageToPasteboard() == false {
            NSSound.beep()
        }
    }

    static func copyLatestFile() {
        if ClipboardManager.shared.copyLatestFileToPasteboard() == false {
            NSSound.beep()
        }
    }

    static func clearClipboardHistory() {
        guard confirm(
            title: "Clear Clipboard History?",
            message: "This removes saved text, image, and file history from Monotch."
        ) else {
            return
        }

        ClipboardManager.shared.clearHistory()
    }

    static func clearCameraRoll() {
        guard confirm(
            title: "Clear Camera Roll?",
            message: "This removes captured Monotch photos and videos from the camera tray and disk."
        ) else {
            return
        }

        CameraCaptureManager.shared.clearCaptures()
    }

    private static func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
