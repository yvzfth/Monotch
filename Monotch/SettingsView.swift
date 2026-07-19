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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                generalSection
                tabSection
                clipboardCardsSection
                systemCardsSection
                shortcutsSection
            }
            .padding(22)
        }
        .frame(width: 580, height: 660)
        .toolbar {
            ToolbarItem {
                HStack(spacing: 6) {
                    shortcutToolbarBadge("Space", "Photo / hold video")
                    shortcutToolbarBadge("\(MonotchShortcutKey.shortTitle(for: previousTabShortcut)) \(MonotchShortcutKey.shortTitle(for: nextTabShortcut))", "Tabs")
                    shortcutToolbarBadgeForRawValue(toggleLyricsShortcut, "Lyrics")
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Monotch Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Choose how Monotch opens, tab order, visible cards, keyboard shortcuts, and the shelf folder.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        settingsCard(title: "General") {
            VStack(alignment: .leading, spacing: 8) {
                settingRow {
                    Toggle("Open when the pointer hovers the notch", isOn: $openOnHover)
                        .font(.system(size: 12, weight: .semibold))
                }

                settingRow {
                    Toggle("Launch Monotch at login", isOn: $launchAtLogin)
                        .font(.system(size: 12, weight: .semibold))
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLaunchAtLogin(enabled)
                        }
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                settingRow {
                    HStack {
                        Text("Language")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Picker("", selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                Text("With hover off, open Monotch from the menu bar commands or ⇧⌘N.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Restart Monotch to Apply Language", isPresented: $showsRelaunchPrompt) {
            Button("Restart Now") { relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Monotch needs to restart for the new language to take effect.")
        }
    }

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

    private var shortcutsSection: some View {
        settingsCard(title: "Shortcuts") {
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow(title: "Previous tab", selection: shortcutBinding($previousTabShortcut))
                shortcutRow(title: "Next tab", selection: shortcutBinding($nextTabShortcut))
                shortcutRow(title: "Toggle lyrics", selection: shortcutBinding($toggleLyricsShortcut))

                Text("Shortcuts work while the notch is expanded. Picking a key already in use moves the old assignment to Off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutRow(title: LocalizedStringKey, selection: Binding<String>) -> some View {
        settingRow {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: selection) {
                    ForEach(MonotchShortcutKey.allCases) { key in
                        Text(key.title).tag(key.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
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

    private var tabSection: some View {
        settingsCard(title: "Tabs") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(tabItems.enumerated()), id: \.element.id) { index, item in
                    reorderRow(
                        title: item.title,
                        isOn: tabVisibilityBinding(for: item),
                        canMoveUp: index > 0,
                        canMoveDown: index < tabItems.count - 1,
                        onMoveUp: { moveTab(item, by: -1) },
                        onMoveDown: { moveTab(item, by: 1) }
                    )
                }
                Text("Disable tabs to remove them from Monotch. Move rows to change their position in the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var clipboardCardsSection: some View {
        settingsCard(title: "Clipboard & Shelf Cards") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(clipboardCards.enumerated()), id: \.element.id) { index, card in
                    reorderRow(
                        title: card.title,
                        isOn: clipboardCardVisibilityBinding(for: card),
                        canMoveUp: index > 0,
                        canMoveDown: index < clipboardCards.count - 1,
                        onMoveUp: { moveClipboardCard(card, by: -1) },
                        onMoveDown: { moveClipboardCard(card, by: 1) }
                    )
                }

                shelfFolderControls

                Text("Turn cards off to remove them. The Shelf card follows the folder above — your Downloads folder unless you choose another.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shelfFolderControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shelf folder")
                        .font(.system(size: 12, weight: .semibold))
                    Text(clipboard.folderShelfURL.path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Choose...") { MonotchCommandCenter.chooseFolderShelfLocation() }
                Button("Open") { MonotchCommandCenter.openFolderShelfLocation() }
            }

            HStack(spacing: 8) {
                Button("Refresh shelf now") { MonotchCommandCenter.refreshFolderShelf() }
                    .buttonStyle(.bordered)

                if clipboard.isFolderShelfCustom {
                    Button("Remove custom folder") { MonotchCommandCenter.resetFolderShelfLocation() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var systemCardsSection: some View {
        settingsCard(title: "Fan/System Cards") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(systemCards.enumerated()), id: \.element.id) { index, card in
                    reorderRow(
                        title: card.title,
                        isOn: systemCardVisibilityBinding(for: card),
                        canMoveUp: index > 0,
                        canMoveDown: index < systemCards.count - 1,
                        onMoveUp: { moveSystemCard(card, by: -1) },
                        onMoveDown: { moveSystemCard(card, by: 1) }
                    )
                }
                Text("CPU, RAM, Storage, Fans, and Sensors can be removed or added back from here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tabItems: [MonotchTabItem] {
        MonotchTabItem.ordered(from: tabOrderRaw)
    }

    private var clipboardCards: [MonotchClipboardCard] {
        MonotchClipboardCard.ordered(from: clipboardCardOrderRaw)
    }

    private var systemCards: [MonotchSystemCard] {
        MonotchSystemCard.ordered(from: systemCardOrderRaw)
    }

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

    // Clipboard trays may all be hidden; the tab then shows an "add a tray"
    // placeholder instead of forcing one card to stay on.
    private func clipboardCardVisibilityBinding(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                source.wrappedValue = newValue
            }
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


    private func settingsCard<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func reorderRow(
        title: String,
        isOn: Binding<Bool>,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Toggle(title, isOn: isOn)
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .disabled(canMoveUp == false)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .disabled(canMoveDown == false)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func shortcutToolbarBadgeForRawValue(_ keyRawValue: String, _ title: LocalizedStringKey) -> some View {
        shortcutToolbarBadge(MonotchShortcutKey.shortTitle(for: keyRawValue), title)
    }

    private func shortcutToolbarBadge(_ key: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}
