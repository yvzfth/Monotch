import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @AppStorage(MonotchSettingsKey.openOnHover) private var openOnHover = true
    @AppStorage(MonotchSettingsKey.appLanguage) private var appLanguageRaw = AppLanguage.system.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var showsRelaunchPrompt = false

    @AppStorage(MonotchSettingsKey.showMediaTab) private var showMediaTab = true
    @AppStorage(MonotchSettingsKey.showClipboardTab) private var showClipboardTab = true
    @AppStorage(MonotchSettingsKey.showSystemTab) private var showSystemTab = true
    @AppStorage(MonotchSettingsKey.showCameraTab) private var showCameraTab = true
    @AppStorage(MonotchSettingsKey.tabOrder) private var tabOrderRaw = MonotchTabItem.defaultOrderRawValue
    @AppStorage(MonotchSettingsKey.clipboardCardOrder) private var clipboardCardOrderRaw = MonotchClipboardCard.defaultOrderRawValue
    @AppStorage(MonotchSettingsKey.showClipboardHistoryCard) private var showClipboardHistoryCard = true
    @AppStorage(MonotchSettingsKey.showClipboardFilesCard) private var showClipboardFilesCard = true
    @AppStorage(MonotchSettingsKey.showClipboardDownloadsCard) private var showClipboardDownloadsCard = true
    @AppStorage(MonotchSettingsKey.systemCardOrder) private var systemCardOrderRaw = MonotchSystemCard.defaultOrderRawValue
    @AppStorage(MonotchSettingsKey.showSystemCPUCard) private var showSystemCPUCard = true
    @AppStorage(MonotchSettingsKey.showSystemRAMCard) private var showSystemRAMCard = true
    @AppStorage(MonotchSettingsKey.showSystemStorageCard) private var showSystemStorageCard = true
    @AppStorage(MonotchSettingsKey.showSystemFansCard) private var showSystemFansCard = true
    @AppStorage(MonotchSettingsKey.showSystemSensorsCard) private var showSystemSensorsCard = true
    @AppStorage(MonotchSettingsKey.previousTabShortcut) private var previousTabShortcut = MonotchShortcutKey.leftArrow.rawValue
    @AppStorage(MonotchSettingsKey.nextTabShortcut) private var nextTabShortcut = MonotchShortcutKey.rightArrow.rawValue
    @AppStorage(MonotchSettingsKey.toggleLyricsShortcut) private var toggleLyricsShortcut = MonotchShortcutKey.l.rawValue

    private let paneWidth: CGFloat = 440

    var body: some View {
        TabView {
            generalPane
                .tabItem { Label(String(localized: "General", comment: "Settings tab."), systemImage: "gearshape") }
            tabsPane
                .tabItem { Label(String(localized: "Tabs", comment: "Settings tab."), systemImage: "square.grid.2x2") }
            cardsPane
                .tabItem { Label(String(localized: "Cards", comment: "Settings tab."), systemImage: "tray.full") }
            shortcutsPane
                .tabItem { Label(String(localized: "Shortcuts", comment: "Settings tab."), systemImage: "keyboard") }
        }
        .frame(width: paneWidth)
        .alert(String(localized: "Restart Monotch to Apply Language", comment: "Language restart alert title."), isPresented: $showsRelaunchPrompt) {
            Button(String(localized: "Restart Now", comment: "Language restart alert confirm.")) { relaunchApp() }
            Button(String(localized: "Later", comment: "Language restart alert dismiss."), role: .cancel) {}
        } message: {
            Text("Monotch needs to restart for the new language to take effect.")
        }
    }

    // MARK: - General

    private var generalPane: some View {
        paneScroll {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(String(localized: "Open when the pointer hovers the notch", comment: "General setting."), isOn: $openOnHover)
                    .toggleStyle(.checkbox)

                Toggle(String(localized: "Launch Monotch at login", comment: "General setting."), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        updateLaunchAtLogin(newValue)
                    }
                ))
                .toggleStyle(.checkbox)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.leading, 20)
                }

                HStack {
                    Text("Language")
                    Spacer()
                    Picker("", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                .padding(.top, 6)

                Text("With hover off, open Monotch from the menu-bar command or ⇧⌘N.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tabs

    private var tabsPane: some View {
        paneScroll {
            VStack(alignment: .leading, spacing: 8) {
                groupHeader(String(localized: "Notch tabs", comment: "Settings group header."))
                listContainer {
                    let items = tabItems
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        reorderRow(
                            title: item.title,
                            isOn: tabVisibilityBinding(for: item),
                            index: index,
                            count: items.count,
                            onMoveUp: { moveTab(item, by: -1) },
                            onMoveDown: { moveTab(item, by: 1) }
                        )
                    }
                }
                footnote(String(localized: "Turn a tab off to hide it. Drag the handle — or use the arrows — to reorder how tabs appear in the notch.", comment: "Tabs footnote."))
            }
        }
    }

    // MARK: - Cards

    private var cardsPane: some View {
        paneScroll {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    groupHeader(String(localized: "Clipboard & Shelf cards", comment: "Settings group header."))
                    listContainer {
                        let cards = clipboardCards
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, cardItem in
                            reorderRow(
                                title: cardItem.title,
                                isOn: clipboardCardVisibilityBinding(for: cardItem),
                                index: index,
                                count: cards.count,
                                onMoveUp: { moveClipboardCard(cardItem, by: -1) },
                                onMoveDown: { moveClipboardCard(cardItem, by: 1) }
                            )
                        }
                        Divider()
                        shelfFolderRow
                    }
                    footnote(String(localized: "The Shelf card mirrors the folder above — your Downloads folder unless you choose another.", comment: "Clipboard cards footnote."))
                }

                VStack(alignment: .leading, spacing: 8) {
                    groupHeader(String(localized: "Fan & System cards", comment: "Settings group header."))
                    listContainer {
                        let cards = systemCards
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, cardItem in
                            reorderRow(
                                title: cardItem.title,
                                isOn: systemCardVisibilityBinding(for: cardItem),
                                index: index,
                                count: cards.count,
                                onMoveUp: { moveSystemCard(cardItem, by: -1) },
                                onMoveDown: { moveSystemCard(cardItem, by: 1) }
                            )
                        }
                    }
                    footnote(String(localized: "CPU, RAM, Storage, Fans and Sensors can be removed or added back at any time.", comment: "System cards footnote."))
                }
            }
        }
    }

    private var shelfFolderRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shelf folder")
                    .font(.system(size: 12, weight: .semibold))
                Text(clipboard.folderShelfURL.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(String(localized: "Choose…", comment: "Choose shelf folder.")) { MonotchCommandCenter.chooseFolderShelfLocation() }
            Button(String(localized: "Open", comment: "Open shelf folder.")) { MonotchCommandCenter.openFolderShelfLocation() }
            Button(String(localized: "Refresh", comment: "Refresh shelf folder.")) { MonotchCommandCenter.refreshFolderShelf() }
            if clipboard.isFolderShelfCustom {
                Button(String(localized: "Reset", comment: "Reset custom shelf folder.")) { MonotchCommandCenter.resetFolderShelfLocation() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Shortcuts

    private var shortcutsPane: some View {
        paneScroll {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    groupHeader(String(localized: "While the notch is open", comment: "Shortcuts group header."))
                    listContainer {
                        kbdRow(keys: ["Space"], title: String(localized: "Take a photo · hold for video", comment: "Shortcut description."), showDivider: true)
                        kbdRow(keys: ["←", "→"], title: String(localized: "Switch between tabs", comment: "Shortcut description."), showDivider: true)
                        kbdRow(keys: ["⌘", "1", "–", "4"], title: String(localized: "Jump straight to a tab", comment: "Shortcut description."), showDivider: true)
                        kbdRow(keys: [MonotchShortcutKey.shortTitle(for: toggleLyricsShortcut)], title: String(localized: "Toggle lyrics", comment: "Shortcut description."), showDivider: false)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    groupHeader(String(localized: "Customize keys", comment: "Shortcuts group header."))
                    listContainer {
                        keyRow(title: String(localized: "Previous tab", comment: "Shortcut row."), binding: shortcutBinding($previousTabShortcut), showDivider: true)
                        keyRow(title: String(localized: "Next tab", comment: "Shortcut row."), binding: shortcutBinding($nextTabShortcut), showDivider: true)
                        keyRow(title: String(localized: "Toggle lyrics", comment: "Shortcut row."), binding: shortcutBinding($toggleLyricsShortcut), showDivider: false)
                    }
                    footnote(String(localized: "Picking a key already in use moves the old assignment to Off.", comment: "Shortcuts footnote."))
                }
            }
        }
    }

    private func keyRow(title: String, binding: Binding<String>, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Picker("", selection: binding) {
                    ForEach(MonotchShortcutKey.allCases) { key in
                        Text(key.title).tag(key.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            if showDivider { Divider() }
        }
    }

    private func kbdRow(keys: [String], title: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key == "–" {
                        Text("–").foregroundStyle(.secondary)
                    } else {
                        KbdCap(text: key)
                    }
                }
                Text(title)
                    .padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            if showDivider { Divider() }
        }
    }

    // MARK: - Reusable layout

    private func paneScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: paneWidth)
        .frame(minHeight: 260, maxHeight: 760)
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func listContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func reorderRow(
        title: String,
        isOn: Binding<Bool>,
        index: Int,
        count: Int,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void
    ) -> some View {
        let canUp = index > 0
        let canDown = index < count - 1
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(action: { if canUp { onMoveUp() } }) {
                    Image(systemName: "chevron.up").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(!canUp)
                Button(action: { if canDown { onMoveDown() } }) {
                    Image(systemName: "chevron.down").frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(!canDown)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            if index < count - 1 { Divider() }
        }
    }

    // MARK: - Bindings & logic

    private var languageBinding: Binding<String> {
        Binding(
            get: { appLanguageRaw },
            set: { newValue in
                guard newValue != appLanguageRaw else { return }
                appLanguageRaw = newValue
                applyLanguagePreference(newValue)
                showsRelaunchPrompt = true
            }
        )
    }

    private func applyLanguagePreference(_ raw: String) {
        if raw == AppLanguage.system.rawValue {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([raw], forKey: "AppleLanguages")
        }
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func shortcutBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                if newValue != MonotchShortcutKey.none.rawValue {
                    if previousTabShortcut == newValue { previousTabShortcut = MonotchShortcutKey.none.rawValue }
                    if nextTabShortcut == newValue { nextTabShortcut = MonotchShortcutKey.none.rawValue }
                    if toggleLyricsShortcut == newValue { toggleLyricsShortcut = MonotchShortcutKey.none.rawValue }
                }
                source.wrappedValue = newValue
            }
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Couldn't update the login item: \(error.localizedDescription)"
        }
    }

    private var tabItems: [MonotchTabItem] { MonotchTabItem.ordered(from: tabOrderRaw) }
    private var clipboardCards: [MonotchClipboardCard] { MonotchClipboardCard.ordered(from: clipboardCardOrderRaw) }
    private var systemCards: [MonotchSystemCard] { MonotchSystemCard.ordered(from: systemCardOrderRaw) }

    private func moveTab(_ item: MonotchTabItem, by offset: Int) {
        var items = tabItems
        move(item, in: &items, by: offset)
        tabOrderRaw = items.map(\.rawValue).joined(separator: ",")
    }

    private func moveClipboardCard(_ card: MonotchClipboardCard, by offset: Int) {
        var cards = clipboardCards
        move(card, in: &cards, by: offset)
        clipboardCardOrderRaw = cards.map(\.rawValue).joined(separator: ",")
    }

    private func moveSystemCard(_ card: MonotchSystemCard, by offset: Int) {
        var cards = systemCards
        move(card, in: &cards, by: offset)
        systemCardOrderRaw = cards.map(\.rawValue).joined(separator: ",")
    }

    private func move<Item: Equatable>(_ item: Item, in items: inout [Item], by offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let newIndex = min(items.count - 1, max(0, index + offset))
        guard newIndex != index else { return }
        items.swapAt(index, newIndex)
    }

    private func tabVisibilityBinding(for item: MonotchTabItem) -> Binding<Bool> {
        switch item {
        case .multimedia: return tabVisibilityBinding($showMediaTab)
        case .clipboard: return tabVisibilityBinding($showClipboardTab)
        case .system: return tabVisibilityBinding($showSystemTab)
        case .camera: return tabVisibilityBinding($showCameraTab)
        }
    }

    private func clipboardCardVisibilityBinding(for card: MonotchClipboardCard) -> Binding<Bool> {
        switch card {
        case .history: return clipboardCardVisibilityBinding($showClipboardHistoryCard)
        case .files: return clipboardCardVisibilityBinding($showClipboardFilesCard)
        case .downloads: return clipboardCardVisibilityBinding($showClipboardDownloadsCard)
        }
    }

    private func systemCardVisibilityBinding(for card: MonotchSystemCard) -> Binding<Bool> {
        switch card {
        case .cpu: return systemCardVisibilityBinding($showSystemCPUCard)
        case .ram: return systemCardVisibilityBinding($showSystemRAMCard)
        case .storage: return systemCardVisibilityBinding($showSystemStorageCard)
        case .fans: return systemCardVisibilityBinding($showSystemFansCard)
        case .sensors: return systemCardVisibilityBinding($showSystemSensorsCard)
        }
    }

    private func tabVisibilityBinding(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                if newValue || enabledTabCount > 1 {
                    source.wrappedValue = newValue
                }
            }
        )
    }

    private func clipboardCardVisibilityBinding(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }

    private func systemCardVisibilityBinding(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                if newValue || enabledSystemCardCount > 1 {
                    source.wrappedValue = newValue
                }
            }
        )
    }

    private var enabledTabCount: Int {
        [showMediaTab, showClipboardTab, showSystemTab, showCameraTab].filter { $0 }.count
    }

    private var enabledSystemCardCount: Int {
        [showSystemCPUCard, showSystemRAMCard, showSystemStorageCard, showSystemFansCard, showSystemSensorsCard].filter { $0 }.count
    }
}

// MARK: - Keyboard cap

private struct KbdCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .frame(minWidth: 26)
            .frame(height: 26)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}
