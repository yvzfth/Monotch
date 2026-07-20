import Combine
import AppKit
import AVFoundation
import SwiftUI

enum WidgetPage: Int, CaseIterable {
    case multimedia
    case clipboard
    case system
    case camera

    static let tabBottomPadding: CGFloat = 18
    private static let utilityExpandedHeight: CGFloat = 362

    var title: String {
        switch self {
        case .multimedia: return "Multimedia"
        case .clipboard:  return "Clipboard"
        case .system:     return "System"
        case .camera:     return "Camera"
        }
    }

    var iconName: String {
        switch self {
        case .multimedia: return "play.circle"
        case .clipboard:  return "doc.on.doc"
        case .system:     return "fan.fill"
        case .camera:     return "camera.fill"
        }
    }

    var expandedHeight: CGFloat {
        switch self {
        case .multimedia: return 148
        case .clipboard, .system: return Self.utilityExpandedHeight
        case .camera: return 228
        }
    }

    var topInset: CGFloat {
        52
    }

    var bottomInset: CGFloat {
        switch self {
        case .multimedia: return 10
        case .clipboard: return 18
        case .system: return Self.tabBottomPadding
        case .camera: return 18
        }
    }
}

private enum SystemStatKind: Equatable {
    case cpu
    case memory
    case storage
}

private enum MediaInlinePanel: Equatable {
    case queue
    case lyrics
}

private enum ClipboardShelfEntry: Identifiable {
    case date(id: String, title: String)
    case image(ClipboardImageItem)
    case text(ClipboardTextItem)

    var id: String {
        switch self {
        case let .date(id, _):
            return "date-\(id)"
        case let .image(item):
            return "image-\(item.id.uuidString)"
        case let .text(item):
            return "text-\(item.id.uuidString)"
        }
    }
}

struct NotchIslandContainerView: View {
    @State private var currentPageIndex: Int = 0
    @State private var sliderValue: Double = 0
    @State private var isScrubbing = false
    @State private var cameraCaptureFlash = false
    @State private var cameraCaptureFlashToken = 0
    @State private var cameraPortraitEnabled = false
    @State private var cameraStudioLightEnabled = false
    @State private var cameraEdgeLightEnabled = false
    @State private var isCameraPreviewExpanded = false
    @State private var cameraRecordPressToken = 0
    @State private var cameraRecordPressActive = false
    @State private var cameraRecordPressStartedRecording = false
    @State private var hoveredCameraCaptureID: UUID?
    @State private var isCameraOpening = false
    @State private var cameraStallHintVisible = false
    @State private var cameraStallToken = 0
    @State private var isCameraPreviewWarm = true
    @State private var cameraPreviewWarmToken = 0
    @State private var copiedTextItemID: UUID?
    @State private var copiedImageItemID: UUID?
    @State private var copiedCameraCaptureID: UUID?
    @State private var mediaInlinePanel: MediaInlinePanel?
    @State private var mediaActionMessage: String?
    @State private var mediaActionMessageToken = 0
    @State private var pendingMediaSharePayload: MediaSharePayload?
    @State private var mediaQueueItems: [String] = []
    @State private var mediaLyricsText = ""
    @State private var mediaLyricsWindow = InlineLyricsWindow(previous: nil, current: "", next: nil)
    @State private var outputVolumeLevel: Double = 0.5
    @State private var isOutputMuted = false
    @State private var lastAudibleVolumeLevel: Double = 0.5
    @State private var isOutputVolumeHovered = false
    @State private var isOutputVolumeScrubbing = false
    @State private var isProgressSliderHovered = false
    @State private var progressSliderHoverValue: Double = 0
    @State private var tabScrollAccumulatedDelta: CGFloat = 0
    @State private var tabScrollGestureConsumed = false
    @State private var tabScrollGestureToken = 0
    @State private var lastTabSwitchDate = Date.distantPast
    @State private var tabTransitionDirection = 1
    @State private var isKeyboardTabSwitchLocked = false
    @State private var mediaScrollAccumulatedDelta: CGFloat = 0
    @State private var mediaScrollGestureConsumed = false
    @State private var mediaScrollGestureToken = 0
    @State private var mediaInfoFlipDirection: CGFloat = 1
    @State private var mediaLyricsTrackKey = ""
    @State private var mediaLyricsRequestToken = 0
    @State private var hoveredSystemStat: SystemStatKind?
    @State private var pendingFanModeSelection: SystemMonitorManager.FanMode?
    @State private var fanModeWarningMessage: String?
    @State private var fanModeWarningToken = 0
    @State private var isConfirmingClearHistory = false
    @Namespace private var fanModeSelectionNamespace
    @ObservedObject private var clipboard = ClipboardManager.shared
    @ObservedObject private var nowPlaying = NowPlayingManager.shared
    @ObservedObject private var camera = CameraCaptureManager.shared
    @ObservedObject private var system = SystemMonitorManager.shared
    @ObservedObject private var ui = NotchUIState.shared
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
    @State private var activeHintPage: WidgetPage?
    @State private var tabHintToken = 0
    @State private var hintIndex = 0
    private let outputVolumeSyncTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    private var activePages: [WidgetPage] {
        let pages = MonotchTabItem.ordered(from: tabOrderRaw)
            .map(\.page)
            .filter { page in
                switch page {
                case .multimedia: return showMediaTab
                case .clipboard: return showClipboardTab
                case .system: return showSystemTab
                case .camera: return showCameraTab
                }
            }

        return pages.isEmpty ? [.multimedia] : pages
    }

    private var currentPage: WidgetPage? {
        guard !activePages.isEmpty else { return nil }
        let safeIndex = (currentPageIndex % activePages.count + activePages.count) % activePages.count
        return activePages[safeIndex]
    }

    var body: some View {
        ZStack {
            notchShape
                .fill(Color.black)
                .overlay(
                    notchShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(ui.isExpanded ? 0.32 : 0.20),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )

            Group {
                if ui.isExpanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .modifier(
                                active: GenieCollapseModifier(isActive: true),
                                identity: GenieCollapseModifier(isActive: false)
                            )
                        ))
                        .zIndex(2)
                } else {
                    collapsedNub
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .padding(.horizontal, currentTailRadius)

        }
        .frame(
            width: ui.isExpanded ? NotchIslandMetrics.expandedWidth : NotchIslandMetrics.collapsedSize.width,
            height: ui.isExpanded ? ui.expandedHeight : NotchIslandMetrics.collapsedSize.height
        )
        .overlay(alignment: .top) {
            if ui.isExpanded {
                topIconBar
                    .padding(.horizontal, currentTailRadius)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .clipShape(notchShape)
        .background(
            // Shadow lives on its own shape layer so content redraws
            // (tab hovers, page transitions, collapse) never re-rasterize it.
            // compositingGroup merges the two stacked shadows into a single
            // layer so their overlap never shows a hard seam along the flat
            // bottom edge when the view redraws on hover.
            notchShape
                .fill(Color.black)
                .shadow(color: .black.opacity(ui.isExpanded ? 0.52 : 0.30), radius: ui.isExpanded ? 12 : 6, y: ui.isExpanded ? 6 : 3)
                .shadow(color: .black.opacity(ui.isExpanded ? 0.28 : 0.14), radius: ui.isExpanded ? 30 : 14, y: ui.isExpanded ? 16 : 8)
                .compositingGroup()
        )
        .contentShape(notchShape)
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            if hovering {
                NotchWindowController.shared.pointerEnteredNotch()
            } else {
                NotchWindowController.shared.pointerLeftNotch()
            }
        }
        .overlay(
            ScrollCaptureView { deltaX, deltaY, location in
                handleScroll(deltaX: deltaX, deltaY: deltaY, location: location)
            }
            .allowsHitTesting(false)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            ui.isExpanded
                ? .spring(response: 0.38, dampingFraction: 0.86)
                : .spring(response: 0.30, dampingFraction: 0.94),
            value: ui.isExpanded
        )
        .onAppear {
            syncExpandedHeight()
            updateVisiblePageWork()
            if ui.isExpanded {
                presentTabHintIfNeeded()
            }
        }
        .onChange(of: normalizedIndex) { _, _ in
            hoveredSystemStat = nil
            if currentPage == .multimedia {
                refreshOutputVolumeLevel()
            }
            updateVisiblePageWork()
            syncExpandedHeight()
        }
        .onChange(of: ui.isExpanded) { _, expanded in
            updateVisiblePageWork()
            syncExpandedHeight()
            if expanded {
                presentTabHintIfNeeded()
            } else {
                hideTabHint()
            }
        }
        .onChange(of: ui.pageRequest) { _, request in
            handlePageRequest(request)
        }
        .onChange(of: currentExpandedHeight) { _, _ in
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
                syncExpandedHeight()
            }
        }
        .onChange(of: isCameraOpening) { _, opening in
            handleCameraOpeningChanged(opening)
        }
        .onChange(of: hoveredSystemStat) { _, _ in
            guard currentPage == .system else { return }
            if hoveredSystemStat == .storage {
                system.refreshStorageCategoriesIfNeeded()
            }
            syncExpandedHeight()
        }
        .onChange(of: isCameraPreviewExpanded) { _, _ in
            guard currentPage == .camera else { return }
            withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                syncExpandedHeight()
            }
        }
        .onChange(of: camera.isPreviewReady) { _, _ in
            updateCameraOpeningState()
        }
        .onChange(of: camera.previewErrorMessage) { _, _ in
            updateCameraOpeningState()
        }
        .onChange(of: system.fanMode) { _, newMode in
            if pendingFanModeSelection == newMode {
                pendingFanModeSelection = nil
            }
        }
        .onReceive(nowPlaying.$playerPosition) { position in
            guard ui.isExpanded, currentPage == .multimedia, isScrubbing == false else { return }
            sliderValue = position
            refreshVisibleLyricsLine()
        }
        .onReceive(nowPlaying.$duration) { duration in
            guard ui.isExpanded, currentPage == .multimedia else { return }
            guard duration > 0 else {
                sliderValue = 0
                return
            }

            sliderValue = min(sliderValue, duration)
        }
        .onReceive(nowPlaying.$title) { _ in
            guard ui.isExpanded, currentPage == .multimedia else { return }
            reloadLyricsIfNeeded()
        }
        .onReceive(nowPlaying.$artist) { _ in
            guard ui.isExpanded, currentPage == .multimedia else { return }
            reloadLyricsIfNeeded()
        }
        .onReceive(nowPlaying.$album) { _ in
            guard ui.isExpanded, currentPage == .multimedia else { return }
            reloadLyricsIfNeeded()
        }
        .onReceive(outputVolumeSyncTimer) { _ in
            guard ui.isExpanded, currentPage == .multimedia else { return }
            if isOutputVolumeScrubbing == false {
                refreshOutputVolumeLevel()
            }
            if mediaInlinePanel == .lyrics, nowPlaying.isPlaying {
                nowPlaying.refreshNowPlayingIfNeeded(minimumInterval: 6.0)
            }
        }
        .background(
            KeyboardShortcutCaptureView { event in
                handleShortcut(event)
            }
            .frame(width: 1, height: 1)
        )
    }

    private func updateVisiblePageWork() {
        let activePage = ui.isExpanded ? currentPage : nil

        system.setMonitoringActive(activePage == .system)
        clipboard.setFolderShelfMonitoringActive(activePage == .clipboard)

        if activePage == .multimedia {
            sliderValue = nowPlaying.playerPosition
            refreshOutputVolumeLevel()
            reloadLyricsIfNeeded()
        }

        if activePage == .system, hoveredSystemStat == .storage {
            system.refreshStorageCategoriesIfNeeded()
        }

        if activePage == .camera {
            syncCameraSystemEffects()
            prepareCameraPreviewWarmup()
        } else {
            resetCameraPreviewWarmup()
            withAnimation(.easeInOut(duration: 0.18)) {
                isCameraOpening = false
            }
        }
    }

    // Hints only show when the notch opens, capped at a few times per app run
    // (not on every tab switch). Tabs with more than one hint cycle through
    // them one at a time, each shown long enough to be read.
    private static var hintPresentationsThisRun = 0
    private static let maxHintPresentationsPerRun = 5

    private func presentTabHintIfNeeded() {
        guard ui.isExpanded, let page = currentPage else { return }
        guard Self.hintPresentationsThisRun < Self.maxHintPresentationsPerRun else { return }
        guard tabHints(page).isEmpty == false else { return }

        Self.hintPresentationsThisRun += 1
        tabHintToken += 1
        hintIndex = 0
        if activeHintPage != page {
            withAnimation(.easeOut(duration: 0.24)) {
                activeHintPage = page
            }
        }

        scheduleHintAdvance(for: page, token: tabHintToken)
    }

    private func hideTabHint() {
        tabHintToken += 1
        if activeHintPage != nil {
            withAnimation(.easeOut(duration: 0.18)) {
                activeHintPage = nil
            }
        }
    }

    private func scheduleHintAdvance(for page: WidgetPage, token: Int) {
        let count = tabHints(page).count

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            guard tabHintToken == token, activeHintPage == page else { return }

            let next = hintIndex + 1
            if next < count {
                withAnimation(.easeOut(duration: 0.28)) {
                    hintIndex = next
                }
                scheduleHintAdvance(for: page, token: token)
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    activeHintPage = nil
                }
            }
        }
    }

    private func tabHints(_ page: WidgetPage) -> [String] {
        switch page {
        case .multimedia:
            let key = MonotchShortcutKey(rawValue: toggleLyricsShortcut) ?? .l
            if key == .none {
                return [String(localized: "Click the quote button for live lyrics", comment: "Hint on the media tab when no lyrics shortcut key is set.")]
            }
            return [String(localized: "Press \(key.shortTitle) or click the quote button for live lyrics", comment: "Hint on the media tab. The placeholder is the lyrics shortcut key, e.g. 'L'.")]
        case .clipboard:
            return [
                String(localized: "Click an item to copy it", comment: "Hint on the clipboard tab."),
                String(localized: "Double-click to open it from the Files or Shelf tray", comment: "Hint on the clipboard tab.")
            ]
        case .system:
            return [
                String(localized: "Click the CPU, RAM, or Storage card for details", comment: "Hint on the system tab."),
                String(localized: "Try fan modes beyond Auto", comment: "Hint on the system tab.")
            ]
        case .camera:
            return [
                String(localized: "Click a capture to copy it", comment: "Hint on the camera tab."),
                String(localized: "Double-click to open it", comment: "Hint on the camera tab."),
                String(localized: "Hold Space to record", comment: "Hint on the camera tab.")
            ]
        }
    }

    private var tabHintOverlay: some View {
        Group {
            if let page = activeHintPage, page == currentPage {
                let hints = tabHints(page)
                let index = min(hintIndex, hints.count - 1)
                if hints.indices.contains(index) {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.42).opacity(0.85))

                        Text(hints[index])
                            .font(.system(size: 8.2, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.60)
                    }
                    .id(index)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func prepareCameraPreviewWarmup() {
        cameraPreviewWarmToken += 1
        isCameraPreviewWarm = true
        updateCameraOpeningState()
    }

    private func resetCameraPreviewWarmup() {
        cameraPreviewWarmToken += 1
        isCameraPreviewWarm = true
    }

    private func updateCameraOpeningState() {
        let shouldOpen = currentPage == .camera
            && ui.isExpanded
            && camera.isPreviewReady == false
            && camera.previewErrorMessage == nil

        withAnimation(.easeInOut(duration: 0.24)) {
            isCameraOpening = shouldOpen
        }
    }

    private func handleCameraOpeningChanged(_ opening: Bool) {
        cameraStallToken += 1

        if opening {
            let token = cameraStallToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard cameraStallToken == token, isCameraOpening else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    cameraStallHintVisible = true
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                cameraStallHintVisible = false
            }
        }
    }

    private var notchShape: BottomRoundedRectangle {
        BottomRoundedRectangle(
            radius: ui.isExpanded ? 28 : 12,
            tailRadius: currentTailRadius,
            tailTopInset: NotchIslandMetrics.topOverlap
        )
    }

    private var currentTailRadius: CGFloat {
        ui.isExpanded ? NotchIslandMetrics.expandedTailRadius : NotchIslandMetrics.collapsedTailRadius
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: currentPage?.topInset ?? 52)
            if let page = currentPage {
                ZStack(alignment: .top) {
                    pageView(page)
                        .frame(maxWidth: .infinity, alignment: .top)

                    if pageNeedsLoadingOverlay(page) {
                        pageLoadingOverlay(page)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(height: contentHeight(for: page), alignment: .top)
                .id(page)
                .transition(pageTransition)
                .animation(.snappy(duration: 0.14, extraBounce: 0.01), value: normalizedIndex)
                .animation(.easeOut(duration: 0.16), value: pageNeedsLoadingOverlay(page))
                .padding(.horizontal, 18)
                .padding(.bottom, page.bottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            tabHintOverlay
        }
    }

    private func syncExpandedHeight() {
        let height = currentExpandedHeight
        guard ui.expandedHeight != height else { return }
        ui.expandedHeight = height
    }

    private var currentExpandedHeight: CGFloat {
        guard let currentPage else { return WidgetPage.multimedia.expandedHeight }
        return expandedHeight(for: currentPage)
    }

    private static let cameraTrayBottomAnchor = "cameraTrayBottomAnchor"
    private static let clipboardCardHeight: CGFloat = 98
    private static let clipboardCardSpacing: CGFloat = 8
    private static let systemStatRowHeight: CGFloat = 58
    private static let systemCardSpacing: CGFloat = 8
    private static let systemFansCardHeight: CGFloat = 134
    private static let systemSensorsCardHeight: CGFloat = 94
    private static let systemDetailPanelHeight: CGFloat = systemDetailPanelFixedHeight

    private func expandedHeight(for page: WidgetPage) -> CGFloat {
        switch page {
        case .camera:
            return cameraExpandedHeight
        case .clipboard:
            return WidgetPage.clipboard.topInset + clipboardContentHeight + WidgetPage.clipboard.bottomInset
        case .system:
            return WidgetPage.system.topInset + systemContentHeight + WidgetPage.system.bottomInset
        case .multimedia:
            return page.expandedHeight + mediaSourceListHeight
        }
    }

    private var clipboardContentHeight: CGFloat {
        let count = CGFloat(visibleClipboardCards.count)
        // With every tray removed, the page keeps one card-height for the
        // "add a tray" placeholder.
        guard count > 0 else { return Self.clipboardCardHeight }
        return count * Self.clipboardCardHeight + max(0, count - 1) * Self.clipboardCardSpacing
    }

    private var systemContentHeight: CGFloat {
        if hoveredSystemStat != nil {
            let statRow = visibleSystemStatCards.isEmpty ? 0 : Self.systemStatRowHeight + Self.systemCardSpacing
            return statRow + Self.systemDetailPanelHeight
        }

        var blocks: [CGFloat] = []
        if visibleSystemStatCards.isEmpty == false {
            blocks.append(Self.systemStatRowHeight)
        }
        for card in visibleSystemUtilityCards {
            switch card {
            case .fans: blocks.append(Self.systemFansCardHeight)
            case .sensors: blocks.append(Self.systemSensorsCardHeight)
            case .cpu, .ram, .storage: break
            }
        }

        guard blocks.isEmpty == false else { return Self.systemStatRowHeight }
        return blocks.reduce(0, +) + CGFloat(blocks.count - 1) * Self.systemCardSpacing
    }

    private func contentHeight(for page: WidgetPage) -> CGFloat {
        if page == .camera {
            return cameraContentHeight
        }

        return max(0, expandedHeight(for: page) - page.topInset - page.bottomInset)
    }

    private func pageNeedsLoadingOverlay(_ page: WidgetPage) -> Bool {
        switch page {
        case .system:
            return systemSnapshotIsReady == false
        case .camera:
            return false
        case .multimedia, .clipboard:
            return false
        }
    }

    private var systemSnapshotIsReady: Bool {
        system.memoryUsed > 0
            || system.diskTotal > 0
            || system.threadCount > 0
            || system.processCount > 0
            || system.fanAvailable
            || system.temperatureReadings.isEmpty == false
    }

    private func pageLoadingOverlay(_ page: WidgetPage) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)

            Text(pageLoadingText(for: page))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.50))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private func pageLoadingText(for page: WidgetPage) -> String {
        switch page {
        case .system:
            return String(localized: "Loading system data", comment: "Shown while system stats are loading.")
        case .camera:
            return String(localized: "Warming camera", comment: "Shown while the camera preview is warming up.")
        case .multimedia:
            return String(localized: "Loading media", comment: "Shown while media info is loading.")
        case .clipboard:
            return String(localized: "Loading clipboard", comment: "Shown while clipboard data is loading.")
        }
    }

    private var cameraPreviewSize: CGSize {
        isCameraPreviewExpanded
            ? CGSize(width: 170, height: 96)
            : CGSize(width: 96, height: 96)
    }

    private var cameraCaptureAspectRatio: CGFloat {
        guard cameraPreviewSize.height > 0 else { return 1 }
        return cameraPreviewSize.width / cameraPreviewSize.height
    }

    private var cameraPreviewCornerRadius: CGFloat {
        isCameraPreviewExpanded ? 20 : 24
    }

    private var cameraUtilityButtonSize: CGFloat {
        24
    }

    private var cameraCaptureButtonSize: CGFloat {
        54
    }

    private var cameraSideControlGap: CGFloat {
        10
    }

    private var cameraUtilityStackHeight: CGFloat {
        cameraUtilityButtonSize * 3 + 6 * 2
    }

    private var cameraCaptureStackHeight: CGFloat {
        cameraCaptureButtonSize
    }

    private var cameraPreviewRowHeight: CGFloat {
        max(cameraPreviewSize.height, max(cameraUtilityStackHeight, cameraCaptureStackHeight))
    }

    private var cameraContentHeight: CGFloat {
        cameraPreviewRowHeight
    }

    private var cameraExpandedHeight: CGFloat {
        WidgetPage.camera.topInset + cameraContentHeight + WidgetPage.camera.bottomInset
    }

    private func handlePageRequest(_ request: NotchPageRequest?) {
        guard let request else { return }
        let targetRawIndex = request.isRelative ? currentPageIndex + request.rawValue : request.rawValue

        if ui.isExpanded == false {
            ui.isExpanded = true
        }

        switchToPageIndex(targetRawIndex, direction: request.direction)
    }

    private func page(forRawIndex rawIndex: Int) -> WidgetPage? {
        guard activePages.isEmpty == false else { return nil }
        let count = activePages.count
        let safeIndex = (rawIndex % count + count) % count
        return activePages[safeIndex]
    }

    private func switchToPageIndex(_ rawIndex: Int, direction: Int) {
        guard let targetPage = page(forRawIndex: rawIndex) else { return }
        let count = activePages.count
        let targetNormalizedIndex = (rawIndex % count + count) % count
        let targetHeight = expandedHeight(for: targetPage)

        guard targetNormalizedIndex != normalizedIndex || targetHeight != ui.expandedHeight else { return }

        tabTransitionDirection = direction

        withAnimation(.snappy(duration: 0.14, extraBounce: 0.01)) {
            currentPageIndex = rawIndex
            ui.expandedHeight = targetHeight
        }
    }

    private var topIconBar: some View {
        // With all 4 tabs enabled, the last tab in the user's order sits on the
        // right edge; fewer tabs stay grouped on the left.
        HStack(spacing: 8) {
            if activePages.count == 4, let lastPage = activePages.last {
                ForEach(activePages.dropLast(), id: \.self) { page in
                    pageIconButton(page: page)
                }

                Spacer()

                pageIconButton(page: lastPage)
            } else {
                ForEach(activePages, id: \.self) { page in
                    pageIconButton(page: page)
                }

                Spacer()
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var pageTransition: AnyTransition {
        let insertionEdge: Edge = tabTransitionDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = tabTransitionDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func pageIconButton(page: WidgetPage) -> some View {
        let isSelected = currentPage == page

        return Button {
            if let index = activePages.firstIndex(of: page) {
                switchToPageIndex(index, direction: index >= normalizedIndex ? 1 : -1)
            }
        } label: {
            Image(systemName: page.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white.opacity(0.92) : .white.opacity(0.52))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.16 : 0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(pageTabItem(for: page).title)
        .contextMenu {
            Button("Hide \(pageTabItem(for: page).title) Tab") {
                hideTab(page)
            }
            .disabled(activePages.count == 1)
        }
    }

    private func pageTabItem(for page: WidgetPage) -> MonotchTabItem {
        switch page {
        case .multimedia: return .multimedia
        case .clipboard: return .clipboard
        case .system: return .system
        case .camera: return .camera
        }
    }

    private func hideTab(_ page: WidgetPage) {
        guard activePages.count > 1 else { return }
        switch page {
        case .multimedia: showMediaTab = false
        case .clipboard: showClipboardTab = false
        case .system: showSystemTab = false
        case .camera: showCameraTab = false
        }
    }

    private func hideClipboardCard(_ card: MonotchClipboardCard) {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            switch card {
            case .history: showClipboardHistoryCard = false
            case .files: showClipboardFilesCard = false
            case .downloads: showClipboardDownloadsCard = false
            }
        }
    }

    private func showClipboardCard(_ card: MonotchClipboardCard) {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.02)) {
            switch card {
            case .history: showClipboardHistoryCard = true
            case .files: showClipboardFilesCard = true
            case .downloads: showClipboardDownloadsCard = true
            }
        }
    }

    private func hideSystemCard(_ card: MonotchSystemCard) {
        guard visibleSystemStatCards.count + visibleSystemUtilityCards.count > 1 else { return }
        switch card {
        case .cpu: showSystemCPUCard = false
        case .ram: showSystemRAMCard = false
        case .storage: showSystemStorageCard = false
        case .fans: showSystemFansCard = false
        case .sensors: showSystemSensorsCard = false
        }
    }

    private func systemCardRemoveButton(_ card: MonotchSystemCard) -> some View {
        Button("Hide \(card.title) Card") {
            hideSystemCard(card)
        }
        .disabled(visibleSystemStatCards.count + visibleSystemUtilityCards.count == 1)
    }

    private var collapsedNub: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 70, height: 3)
                .padding(.bottom, 6)
        }
    }

    private var normalizedIndex: Int {
        guard !activePages.isEmpty else { return 0 }
        let count = activePages.count
        return (currentPageIndex % count + count) % count
    }

    private var currentMediaTrackKey: String {
        [
            nowPlaying.title,
            nowPlaying.artist,
            nowPlaying.album
        ]
        .map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .joined(separator: "|")
    }

    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat, location: CGPoint) {
        guard ui.isExpanded else { return }
        guard !activePages.isEmpty else { return }

        if abs(deltaX) > abs(deltaY) * 1.12 {
            if shouldReserveHorizontalScroll(at: location) {
                resetTabScrollGesture()
                return
            }

            if handleTabScroll(deltaX: deltaX) {
                return
            }
        }

        if currentPage == .multimedia {
            _ = handleMediaInfoScroll(deltaY: deltaY)
        }
    }

    private func shouldReserveHorizontalScroll(at location: CGPoint) -> Bool {
        let yFromTop = ui.expandedHeight - location.y

        switch currentPage {
        case .clipboard:
            let contentTop = WidgetPage.clipboard.topInset - 4
            let contentBottom = WidgetPage.clipboard.topInset + clipboardContentHeight + 8
            return yFromTop >= contentTop && yFromTop <= contentBottom

        case .camera:
            let trayTop = WidgetPage.camera.topInset + cameraPreviewRowHeight + 4
            let trayBottom = ui.expandedHeight - WidgetPage.camera.bottomInset + 6
            return yFromTop >= trayTop && yFromTop <= trayBottom

        default:
            return false
        }
    }

    private func handleTabScroll(deltaX: CGFloat) -> Bool {
        guard abs(deltaX) > 0.15 else { return true }

        tabScrollGestureToken += 1
        let token = tabScrollGestureToken
        tabScrollAccumulatedDelta += deltaX

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard tabScrollGestureToken == token else { return }
            tabScrollAccumulatedDelta = 0
            tabScrollGestureConsumed = false
        }

        guard tabScrollGestureConsumed == false,
              abs(tabScrollAccumulatedDelta) >= 18 else {
            return true
        }

        // Even while scrolling continuously, hold each tab for at least 0.3 s.
        guard Date().timeIntervalSince(lastTabSwitchDate) >= 0.3 else {
            return true
        }

        tabScrollGestureConsumed = true
        lastTabSwitchDate = Date()
        let direction = tabScrollAccumulatedDelta > 0 ? -1 : 1
        switchToPageIndex(currentPageIndex + direction, direction: direction)
        return true
    }

    private func resetTabScrollGesture() {
        tabScrollGestureToken += 1
        tabScrollAccumulatedDelta = 0
        tabScrollGestureConsumed = false
    }

    private func handleMediaInfoScroll(deltaY: CGFloat) -> Bool {
        guard abs(deltaY) > 0.15 else { return true }

        mediaScrollGestureToken += 1
        let token = mediaScrollGestureToken
        mediaScrollAccumulatedDelta += deltaY

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard mediaScrollGestureToken == token else { return }
            mediaScrollAccumulatedDelta = 0
            mediaScrollGestureConsumed = false
        }

        guard mediaScrollGestureConsumed == false,
              abs(mediaScrollAccumulatedDelta) >= 18 else {
            return true
        }

        mediaScrollGestureConsumed = true
        mediaInfoFlipDirection = mediaScrollAccumulatedDelta > 0 ? 1 : -1
        if mediaInlinePanel == .lyrics {
            showSongInfoInMediaInfo()
        } else {
            showLyricsInMediaInfo()
        }

        return true
    }

    @ViewBuilder
    private func pageView(_ page: WidgetPage) -> some View {
        switch page {
        case .multimedia:
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    artworkView

                    mediaInfoArea
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26), value: mediaInlinePanel)

                    HStack(spacing: 6) {
                        mediaButton(systemName: "backward.fill", size: 24, fontSize: 10) {
                            nowPlaying.previousTrack()
                        }
                        mediaButton(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill") {
                            nowPlaying.togglePlayPause()
                        }
                        mediaButton(systemName: "forward.fill", size: 24, fontSize: 10) {
                            nowPlaying.nextTrack()
                        }
                    }
                }

                mediaBottomArea

                if extraMediaSources.isEmpty == false {
                    mediaSourceList
                }
            }
            .frame(height: 76 + mediaSourceListHeight)
        case .clipboard:
            clipboardPage
        case .system:
            systemPage
        case .camera:
            cameraPage
        }
    }

    private var systemPage: some View {
        return VStack(spacing: 8) {
            if visibleSystemStatCards.isEmpty == false {
                HStack(spacing: 8) {
                    ForEach(visibleSystemStatCards, id: \.self) { card in
                        systemStatTile(for: card)
                    }
                }
            }

            if let hoveredSystemStat {
                systemDetailPanel(for: hoveredSystemStat)
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                            .combined(with: .offset(y: -8)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    ))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        setHoveredSystemStat(nil)
                    }
            } else {
                fanControlPanel
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: hoveredSystemStat)
        .frame(height: systemPageHeight, alignment: .top)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    setHoveredSystemStat(nil)
                }
        )
    }

    private func setHoveredSystemStat(_ kind: SystemStatKind?) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            hoveredSystemStat = kind
            syncExpandedHeight()
        }
    }

    private var visibleSystemStatCards: [MonotchSystemCard] {
        MonotchSystemCard.ordered(from: systemCardOrderRaw).filter { card in
            switch card {
            case .cpu: return showSystemCPUCard
            case .ram: return showSystemRAMCard
            case .storage: return showSystemStorageCard
            case .fans, .sensors: return false
            }
        }
    }

    @ViewBuilder
    private func systemStatTile(for card: MonotchSystemCard) -> some View {
        Group {
            switch card {
            case .cpu:
                systemStatTile(kind: .cpu, title: card.title, usedText: percentText(system.cpuUsage), freeText: idleSuffixText(percentText(system.cpuIdleUsage)), progress: system.cpuUsage)
            case .ram:
                systemStatTile(kind: .memory, title: card.title, usedText: memoryText(system.memoryUsed), freeText: freeSuffixText(memoryText(system.memoryFree)), progress: system.memoryProgress)
            case .storage:
                systemStatTile(kind: .storage, title: card.title, usedText: byteText(system.diskUsed), freeText: freeSuffixText(byteText(system.diskFree)), progress: system.diskProgress)
            case .fans, .sensors:
                EmptyView()
            }
        }
        .contextMenu {
            systemCardRemoveButton(card)
        }
    }

    private var systemPageHeight: CGFloat {
        contentHeight(for: .system)
    }

    private func usedSummaryText(_ value: String) -> String {
        String(localized: "\(value) Used", comment: "An amount followed by the word Used, e.g. '40% Used'.")
    }

    private func idleSuffixText(_ value: String) -> String {
        String(localized: "\(value) idle", comment: "A percentage followed by the word idle, e.g. '40% idle'.")
    }

    private func freeSuffixText(_ value: String) -> String {
        String(localized: "\(value) free", comment: "An amount followed by the word free, e.g. '4 GB free'.")
    }

    private func freePrefixText(_ value: String) -> String {
        String(localized: "Free \(value)", comment: "The word Free followed by an amount, e.g. 'Free 4 GB'.")
    }

    private func systemStatTile(kind: SystemStatKind, title: String, usedText: String, freeText: String, progress: Double) -> some View {
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                Spacer(minLength: 0)
                Text(usedText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(systemProgressTint(progress))
                        .frame(width: max(5, proxy.size.width * min(1, max(0, progress))))
                }
            }
            .frame(height: 5)

            Text(freeText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.44))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.white.opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hoveredSystemStat == kind ? Color.white.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            setHoveredSystemStat(hoveredSystemStat == kind ? nil : kind)
        }
    }

    private func systemDetailHeader(_ title: String, summary: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.88))

            Spacer(minLength: 0)

            Text(summary)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
    }

    private func systemDetailDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private func systemDetailLegendPill(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 8.6, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 0)
            systemDetailValueText(value)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(Color.white.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func systemDetailTag(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)
            Text(text)
                .font(.system(size: 8.4, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .background(Color.white.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func systemDetailBottomMetric(_ title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9.2, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.46))
                .lineLimit(1)
            Spacer(minLength: 0)
            systemDetailValueText(value)
        }
        .frame(maxWidth: .infinity)
    }

    private func systemDetailValueText(_ value: String, color: Color = Color.white.opacity(0.86)) -> some View {
        Text(value)
            .font(.system(size: 9.6, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
    }

    private func systemDetailMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.system(size: 7.8, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.56))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 7.8, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var cpuDetailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            systemDetailHeader(
                String(localized: "CPU", comment: "The CPU detail panel title."),
                summary: usedSummaryText(precisePercentText(system.cpuUsage))
            )

            stackedSystemBar([
                (system.cpuSystemUsage, cpuSystemColor),
                (system.cpuUserUsage, cpuUserColor),
                (system.cpuIdleUsage, cpuIdleColor)
            ])

            HStack(spacing: 7) {
                cpuUsagePill(String(localized: "System", comment: "System CPU usage."), value: precisePercentText(system.cpuSystemUsage), color: cpuSystemColor)
                cpuUsagePill(String(localized: "User", comment: "User CPU usage."), value: precisePercentText(system.cpuUserUsage), color: cpuUserColor)
                cpuUsagePill(String(localized: "Idle", comment: "Idle CPU usage."), value: precisePercentText(system.cpuIdleUsage), color: cpuIdleColor)
            }

            systemDetailDivider()

            HStack(spacing: 16) {
                cpuBottomMetric(String(localized: "Threads", comment: "The thread count metric."), value: countText(system.threadCount))
                cpuBottomMetric(String(localized: "Processes", comment: "The process count metric."), value: countText(system.processCount))
            }
        }
        .systemDetailPanelStyle()
    }

    private func cpuUsagePill(_ title: String, value: String, color: Color) -> some View {
        systemDetailLegendPill(title, value: value, color: color)
    }

    private func cpuBottomMetric(_ title: String, value: String) -> some View {
        systemDetailBottomMetric(title, value: value)
    }

    private var cpuSystemColor: Color {
        Color(red: 1.00, green: 0.36, blue: 0.34)
    }

    private var cpuUserColor: Color {
        Color(red: 0.32, green: 0.64, blue: 1.00)
    }

    private var cpuIdleColor: Color {
        Color.white.opacity(0.36)
    }

    private var memoryDetailPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            systemDetailHeader(
                String(localized: "RAM", comment: "The RAM detail panel title."),
                summary: usedSummaryText("\(memoryText(system.memoryUsed)) / \(memoryText(system.memoryTotal))")
            )

            memoryStackedUsageBar

            HStack(spacing: 7) {
                memoryUsagePill(String(localized: "App", comment: "App memory usage."), value: memoryText(system.memoryApp), color: memoryAppColor)
                memoryUsagePill(String(localized: "Wired", comment: "Wired memory usage."), value: memoryText(system.memoryWired), color: memoryWiredColor)
                memoryUsagePill(String(localized: "Compressed", comment: "Compressed memory usage."), value: memoryText(system.memoryCompressed), color: memoryCompressedColor)
            }

            systemDetailDivider()

            HStack(spacing: 16) {
                memoryBottomMetric(String(localized: "Cached", comment: "Cached memory metric."), value: memoryText(system.memoryCached))
                memoryBottomMetric(String(localized: "Swap", comment: "Swap memory metric."), value: memoryText(system.memorySwapUsed))
            }
        }
        .systemDetailPanelStyle()
    }

    private var memoryStackedUsageBar: some View {
        let total = max(Double(system.memoryTotal), 1)
        let app = min(1, max(0, Double(system.memoryApp) / total))
        let wired = min(1 - app, max(0, Double(system.memoryWired) / total))
        let compressed = min(1 - app - wired, max(0, Double(system.memoryCompressed) / total))
        let free = max(0, 1 - app - wired - compressed)

        return GeometryReader { proxy in
            HStack(spacing: 1) {
                memoryBarSegment(app, color: memoryAppColor, proxy: proxy)
                memoryBarSegment(wired, color: memoryWiredColor, proxy: proxy)
                memoryBarSegment(compressed, color: memoryCompressedColor, proxy: proxy)
                memoryBarSegment(free, color: memoryFreeColor, proxy: proxy)
            }
            .clipShape(Capsule())
            .background(
                Capsule()
                    .fill(memoryFreeColor)
            )
        }
        .frame(height: 9)
    }

    private func memoryBarSegment(_ fraction: Double, color: Color, proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, proxy.size.width * min(1, max(0, fraction))))
    }

    private func memoryUsagePill(_ title: String, value: String, color: Color) -> some View {
        systemDetailLegendPill(title, value: value, color: color)
    }

    private func memoryBottomMetric(_ title: String, value: String) -> some View {
        systemDetailBottomMetric(title, value: value)
    }

    private func memoryValueText(_ value: String, color: Color) -> some View {
        systemDetailValueText(value, color: color)
    }

    private var memoryAppColor: Color {
        Color(red: 1.00, green: 0.68, blue: 0.12)
    }

    private var memoryWiredColor: Color {
        Color(red: 0.62, green: 0.48, blue: 0.95)
    }

    private var memoryCompressedColor: Color {
        Color(red: 0.18, green: 0.78, blue: 0.72)
    }

    private var memoryFreeColor: Color {
        Color.white.opacity(0.085)
    }

    private func stackedSystemBar(_ segments: [(Double, Color)]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.1)
                        .frame(width: max(0, proxy.size.width * min(1, max(0, segment.0))))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(Capsule())
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
        }
        .frame(height: 9)
    }

    private func storageLegend(_ title: String, _ color: Color) -> some View {
        systemDetailTag(title, color: color)
    }

    private func storageCategoryLegend(_ category: SystemMonitorManager.StorageCategory) -> some View {
        systemDetailTag("\(category.kind.storageTitle) \(byteText(category.bytes))", color: category.kind.storageColor)
    }

    private var visibleStorageCategories: [SystemMonitorManager.StorageCategory] {
        let categories = system.diskCategories.filter { $0.bytes > 0 }
        if categories.isEmpty {
            return [
                SystemMonitorManager.StorageCategory(kind: .systemData, bytes: system.diskUsed)
            ]
        }

        return categories
    }

    @ViewBuilder
    private func systemDetailPanel(for kind: SystemStatKind) -> some View {
        switch kind {
        case .cpu:
            cpuDetailPanel

        case .memory:
            memoryDetailPanel

        case .storage:
            let storageCategories = visibleStorageCategories
            let storageSegments = storageCategories.map { category in
                (system.diskTotal > 0 ? Double(category.bytes) / Double(system.diskTotal) : 0, category.kind.storageColor)
            } + [
                (system.diskTotal > 0 ? Double(system.diskFree) / Double(system.diskTotal) : 0, Color.white.opacity(0.22))
            ]

            VStack(alignment: .leading, spacing: 8) {
                systemDetailHeader("Macintosh HD", summary: usedSummaryText("\(byteText(system.diskUsed)) / \(byteText(system.diskTotal))"))

                stackedSystemBar(storageSegments)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(storageCategories.prefix(5)) { category in
                            storageCategoryLegend(category)
                        }
                        storageLegend(freePrefixText(byteText(system.diskFree)), Color.white.opacity(0.40))
                    }
                }
                .frame(height: 24)

                systemDetailDivider()

                HStack(spacing: 16) {
                    systemDetailBottomMetric(String(localized: "Used", comment: "Storage used metric label."), value: byteText(system.diskUsed))
                    systemDetailBottomMetric(String(localized: "Free", comment: "Storage free metric label."), value: byteText(system.diskFree))
                }
            }
            .systemDetailPanelStyle()
        }
    }

private var fanControlPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(visibleSystemUtilityCards, id: \.self) { card in
            Group {
                switch card {
                case .fans:
                    // Pinned so the rendered height always matches the budget
                    // used by systemContentHeight; otherwise the card grows
                    // into the bottom inset and the padding looks uneven.
                    fanControlsCard
                        .frame(height: Self.systemFansCardHeight)
                case .sensors:
                    fanSensorsCard
                        .frame(height: Self.systemSensorsCardHeight)
                case .cpu, .ram, .storage:
                    EmptyView()
                }
            }
            .contextMenu {
                systemCardRemoveButton(card)
            }
        }
    }
}

private var visibleSystemUtilityCards: [MonotchSystemCard] {
    MonotchSystemCard.ordered(from: systemCardOrderRaw).filter { card in
        switch card {
        case .fans:
            // Fanless Macs (e.g. MacBook Air) hide fan controls automatically.
            return showSystemFansCard && (system.fanAvailable || SystemMonitorManager.modelLikelyHasFan)
        case .sensors: return showSystemSensorsCard
        case .cpu, .ram, .storage: return false
        }
    }
}

private var fanControlsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Fan Controls")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            fanModeSelector
        }

        if system.fanReadings.isEmpty {
            fanUnavailableCard
        } else {
            HStack(spacing: 8) {
                ForEach(Array(system.fanReadings.prefix(2).enumerated()), id: \.offset) { index, fan in
                    fanDetailCard(
                        fan,
                        title: index == 0
                            ? String(localized: "LEFT FAN", comment: "The left fan label.")
                            : String(localized: "RIGHT FAN", comment: "The right fan label."),
                        tint: index == 0 ? fanBlueColor : fanPurpleColor
                    )
                }
            }
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.white.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.07), lineWidth: 1)
    )
}

private var fanSensorsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
            Text("SENSORS")
                .font(.system(size: 8.2, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.36))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let hottest = hottestTemperatureReading {
                HStack(spacing: 3) {
                    Text("hottest:")
                        .foregroundColor(.white.opacity(0.42))
                    Text("\(hottest.kind.temperatureTitle) \(temperatureText(hottest.celsius))")
                        .foregroundColor(Color(red: 1.00, green: 0.70, blue: 0.26).opacity(0.92))
                }
                .font(.system(size: 8.2, weight: .semibold, design: .rounded))
                .lineLimit(1)
            } else {
                Text("temperatures unavailable")
                    .font(.system(size: 8.2, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }

        HStack(spacing: 6) {
            ForEach(SystemMonitorManager.TemperatureReading.Kind.allCases, id: \.self) { kind in
                fanTemperatureTile(kind, reading: temperatureReading(for: kind))
            }
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.white.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.07), lineWidth: 1)
    )
}

    private var fanModeSelector: some View {
        HStack(spacing: 2) {
            fanModeSegment(SystemMonitorManager.FanMode.automatic.title, isSelected: visibleFanMode == .automatic, isEnabled: fanControlButtonsEnabled) {
                selectFanMode(.automatic)
            }
            fanModeSegment(SystemMonitorManager.FanMode.silent.title, isSelected: visibleFanMode == .silent, isEnabled: fanControlButtonsEnabled) {
                selectFanMode(.silent)
            }
            fanModeSegment(SystemMonitorManager.FanMode.balanced.title, isSelected: visibleFanMode == .balanced, isEnabled: fanControlButtonsEnabled) {
                selectFanMode(.balanced)
            }
            fanModeSegment(SystemMonitorManager.FanMode.performance.title, isSelected: visibleFanMode == .performance, isEnabled: fanControlButtonsEnabled) {
                selectFanMode(.performance)
            }
            fanModeSegment(SystemMonitorManager.FanMode.maximum.title, isSelected: visibleFanMode == .maximum, isEnabled: fanControlButtonsEnabled) {
                selectFanMode(.maximum)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let fanModeWarningMessage {
                Text(fanModeWarningMessage)
                    .font(.system(size: 7.8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.56, blue: 0.32))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 1.0, green: 0.56, blue: 0.32).opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                    .offset(y: 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .allowsHitTesting(false)
            }
        }
        .zIndex(2)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: visibleFanMode)
        .animation(.easeOut(duration: 0.14), value: fanModeWarningMessage)
    }

    private var visibleFanMode: SystemMonitorManager.FanMode {
        pendingFanModeSelection ?? system.fanMode
    }

    private func selectFanMode(_ mode: SystemMonitorManager.FanMode) {
        let isThermallyBlocked = isQuietFanModeThermallyBlocked(mode)
        let optimisticMode: SystemMonitorManager.FanMode = isThermallyBlocked ? .automatic : mode

        if isThermallyBlocked {
            showFanModeWarning(for: mode)
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            pendingFanModeSelection = optimisticMode
        }

        let appliedMode = system.setFanMode(mode)
        if appliedMode != optimisticMode {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                pendingFanModeSelection = appliedMode
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if pendingFanModeSelection == appliedMode {
                pendingFanModeSelection = nil
            }
        }
    }

    private func isQuietFanModeThermallyBlocked(_ mode: SystemMonitorManager.FanMode) -> Bool {
        guard mode == .silent || mode == .balanced else { return false }
        guard let cpuTemperature = temperatureReading(for: .cpu)?.celsius else { return false }
        return cpuTemperature >= SystemMonitorManager.quietFanModeThermalLimitCelsius
    }

    private func showFanModeWarning(for mode: SystemMonitorManager.FanMode) {
        fanModeWarningToken += 1
        let token = fanModeWarningToken
        let modeTitle = mode.title
        let cpuText = temperatureReading(for: .cpu).map { temperatureText($0.celsius) }
            ?? String(localized: "hot", comment: "Fallback CPU temperature description when a reading isn't available.")

        withAnimation(.easeOut(duration: 0.14)) {
            fanModeWarningMessage = String(
                localized: "\(modeTitle) blocked: CPU \(cpuText)",
                comment: "A warning shown when a quiet fan mode is blocked because the CPU is too hot. First argument is the fan mode name, second is the CPU temperature."
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard fanModeWarningToken == token else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                fanModeWarningMessage = nil
            }
        }
    }

    private func fanModeSegment(_ title: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8.4, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(isEnabled ? (isSelected ? 0.92 : 0.44) : 0.24))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .padding(.horizontal, 10)
                .frame(minWidth: 42, minHeight: 24)
                .background {
                    if isSelected && isEnabled {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .matchedGeometryEffect(id: "fanModeSelection", in: fanModeSelectionNamespace)
                            .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }


    private var fanControlButtonsEnabled: Bool {
        system.fanControlAvailable
    }

    private var fanUnavailableCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.26))
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(system.fanStatusText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.66))
                    .lineLimit(1)

                Text("Fan telemetry is not available")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func fanDetailCard(_ fan: SystemMonitorManager.FanReading, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            fanRPMIcon(fan.currentRPM, tint: tint, size: 54, fanID: fan.id)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 8.2, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(rpmNumberText(fan.currentRPM))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.numericText(value: fan.currentRPM))
                    Text("rpm")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(4, proxy.size.width * fanProgress(fan)))
                    }
                }
                .frame(height: 4)

                Text("\(Int((fanProgress(fan) * 100).rounded()))% of \(rpmNumberText(fan.maximumRPM)) max")
                    .font(.system(size: 7.8, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 74)
        .animation(.easeInOut(duration: 0.6), value: fan.currentRPM)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.07), Color.black.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func fanRPMIcon(_ rpm: Double, tint: Color, size: CGFloat, fanID: Int) -> some View {
        FanRotorIcon(
            fanID: fanID,
            rpm: rpm,
            tint: tint,
            size: size
        )
    }

    private func fanTemperatureTile(
        _ kind: SystemMonitorManager.TemperatureReading.Kind,
        reading: SystemMonitorManager.TemperatureReading?
    ) -> some View {
        let celsius = reading?.celsius
        let tint = temperatureTint(celsius)

        return VStack(alignment: .leading, spacing: 5) {
            Text(kind.temperatureTitle)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(celsius.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(tint.opacity(celsius == nil ? 0.34 : 0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("°C")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(celsius == nil ? 0.22 : 0.38))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, proxy.size.width * temperatureProgress(celsius)))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    private func temperatureReading(for kind: SystemMonitorManager.TemperatureReading.Kind) -> SystemMonitorManager.TemperatureReading? {
        system.temperatureReadings.first { $0.kind == kind }
    }

    private var hottestTemperatureReading: SystemMonitorManager.TemperatureReading? {
        system.temperatureReadings.max { $0.celsius < $1.celsius }
    }

    private func temperatureText(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }

    private func temperatureProgress(_ celsius: Double?) -> CGFloat {
        guard let celsius else { return 0 }
        return CGFloat(min(1, max(0, celsius / 100)))
    }

    private func temperatureTint(_ celsius: Double?) -> Color {
        guard let celsius else { return .white.opacity(0.30) }

        if celsius >= 75 {
            return Color(red: 1.00, green: 0.34, blue: 0.30)
        }

        if celsius >= 55 {
            return Color(red: 1.00, green: 0.70, blue: 0.26)
        }

        if celsius >= 42 {
            return Color(red: 0.36, green: 0.72, blue: 1.00)
        }

        return Color(red: 0.28, green: 0.86, blue: 0.50)
    }

    private func fanProgress(_ fan: SystemMonitorManager.FanReading) -> CGFloat {
        guard fan.maximumRPM > 0 else { return 0 }
        return CGFloat(min(1, max(0, fan.currentRPM / fan.maximumRPM)))
    }

    private func rpmNumberText(_ value: Double) -> String {
        countText(Int(value.rounded()))
    }

    private var fanBlueColor: Color {
        Color(red: 0.38, green: 0.66, blue: 1.00)
    }

    private var fanPurpleColor: Color {
        Color(red: 0.62, green: 0.48, blue: 1.00)
    }

    private var fanStatusColor: Color {
        if system.fanHelperRequiresApproval {
            return Color(red: 1.00, green: 0.72, blue: 0.34).opacity(0.84)
        }

        if system.fanWriteAccessDenied || system.fanLastWriteFailed {
            return Color(red: 1.00, green: 0.56, blue: 0.42).opacity(0.78)
        }

        return .white.opacity(0.42)
    }

private var clipboardPage: some View {
    VStack(alignment: .leading, spacing: 8) {
        if visibleClipboardCards.isEmpty {
            clipboardEmptyTraysCard
        } else {
            ForEach(visibleClipboardCards, id: \.self) { card in
                clipboardCardView(card)
                    .contextMenu {
                        Button("Hide \(card.title) Card") {
                            hideClipboardCard(card)
                        }
                    }
            }
        }
    }
    .frame(height: clipboardPageHeight, alignment: .top)
}

private var clipboardEmptyTraysCard: some View {
    VStack(spacing: 10) {
        Text("No trays here — add one to get started")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.72)

        HStack(spacing: 6) {
            ForEach(MonotchClipboardCard.ordered(from: clipboardCardOrderRaw)) { card in
                clipboardAddTrayButton(card)
            }
        }
    }
    .frame(maxWidth: .infinity, minHeight: Self.clipboardCardHeight)
    .background(clipboardTrayBackground)
}

private func clipboardAddTrayButton(_ card: MonotchClipboardCard) -> some View {
    Button {
        showClipboardCard(card)
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 7.5, weight: .bold))
            Text(card.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.80))
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .help(String(localized: "Add the \(card.title) tray", comment: "Tooltip for a button that re-adds a hidden clipboard tray. The placeholder is the tray name."))
}

private func clipboardTrayRemoveButton(for card: MonotchClipboardCard) -> some View {
    ShelfRemoveButton {
        hideClipboardCard(card)
    }
}

@ViewBuilder
private func clipboardCardView(_ card: MonotchClipboardCard) -> some View {
    switch card {
    case .history:
        clipboardTextShelf
    case .files:
        FileShelfView(
            title: MonotchClipboardCard.files.title,
            items: Binding(
                get: { clipboard.recentFileItems },
                set: { clipboard.recentFileItems = $0 }
            ),
            onRemove: {
                hideClipboardCard(.files)
            }
        )
    case .downloads:
        FolderShelfView(
            title: clipboard.folderShelfTitle,
            items: clipboard.folderShelfItems,
            onChooseFolder: {
                ui.isInteractionHeld = true
                clipboard.chooseFolderShelfLocation()
                ui.isInteractionHeld = false
            },
            onRefresh: {
                clipboard.refreshFolderShelf()
            },
            onRemove: {
                hideClipboardCard(.downloads)
            }
        )
    }
}

private var visibleClipboardCards: [MonotchClipboardCard] {
    MonotchClipboardCard.ordered(from: clipboardCardOrderRaw).filter { card in
        switch card {
        case .history: return showClipboardHistoryCard
        case .files: return showClipboardFilesCard
        case .downloads: return showClipboardDownloadsCard
        }
    }
}

    private var clipboardPageHeight: CGFloat {
        contentHeight(for: .clipboard)
    }

    private var clipboardTextShelf: some View {
        VStack(alignment: .leading, spacing: 4) {
            let entries = clipboardShelfEntries
            let hasClipboardItems = entries.isEmpty == false

            HStack {
                Text("Clipboard")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))

                Spacer()

                if hasClipboardItems {
                    if isConfirmingClearHistory {
                        inlineConfirmPill(
                            message: String(localized: "Clear items?", comment: "Inline confirmation to clear all items from a tray."),
                            onConfirm: {
                                withAnimation(.easeOut(duration: 0.16)) { isConfirmingClearHistory = false }
                                clipboard.recentTextItems.removeAll()
                                clipboard.recentImageItems.removeAll()
                            },
                            onCancel: {
                                withAnimation(.easeOut(duration: 0.16)) { isConfirmingClearHistory = false }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { isConfirmingClearHistory = true }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.72))
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Clear items", comment: "Tooltip for the button that clears all items from the clipboard history tray."))
                    }
                }

                clipboardTrayRemoveButton(for: .history)
            }
            .frame(height: 22)

            GeometryReader { proxy in
                let spacing: CGFloat = 8
                let trayHorizontalInset: CGFloat = 8
                let availableWidth = proxy.size.width
                let maxTileWidth = min(184, availableWidth)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        if hasClipboardItems == false {
                            Text("Copied text appears here")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.42))
                                .frame(width: max(1, availableWidth - trayHorizontalInset * 2), height: 56, alignment: .leading)
                        } else {
                            ForEach(entries) { entry in
                                clipboardShelfEntryView(entry, maxTileWidth: maxTileWidth)
                            }
                        }
                    }
                    .padding(.horizontal, trayHorizontalInset)
                }
                .frame(height: 72)
                .background(clipboardTrayBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(height: 72)
        }
    }

    private var clipboardShelfEntries: [ClipboardShelfEntry] {
        let payloads: [(date: Date, entry: ClipboardShelfEntry)] =
            clipboard.recentImageItems.map { ($0.createdAt, .image($0)) }
            + clipboard.recentTextItems.map { ($0.createdAt, .text($0)) }

        let sortedPayloads = payloads.sorted { first, second in
            if first.date == second.date {
                return first.entry.id < second.entry.id
            }
            return first.date > second.date
        }

        var entries: [ClipboardShelfEntry] = []
        var lastDayID: String?
        for payload in sortedPayloads {
            let dayID = clipboardDayID(for: payload.date)
            if dayID != lastDayID {
                if Calendar.current.isDateInToday(payload.date) == false {
                    entries.append(.date(id: dayID, title: clipboardDayTitle(for: payload.date)))
                }
                lastDayID = dayID
            }
            entries.append(payload.entry)
        }
        return entries
    }

    @ViewBuilder
    private func clipboardShelfEntryView(_ entry: ClipboardShelfEntry, maxTileWidth: CGFloat) -> some View {
        switch entry {
        case let .date(_, title):
            clipboardDateSeparator(title)
        case let .image(item):
            clipboardImageItem(item)
        case let .text(item):
            clipboardTextItem(
                item,
                width: clipboardTextWidth(for: item.text, maxWidth: maxTileWidth)
            )
        }
    }

    private func clipboardDateSeparator(_ title: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.42))
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 12, height: 36)

            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 14)
        }
        .frame(width: 18, height: 54)
        .accessibilityHidden(true)
    }

    private func clipboardDayID(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func clipboardDayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today", comment: "The clipboard history date separator for today.")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday", comment: "The clipboard history date separator for yesterday.")
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private var clipboardTrayBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func clipboardTextWidth(for text: String, maxWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        let lines = text.components(separatedBy: .newlines).prefix(3)
        let measuredWidth = lines.reduce(CGFloat(0)) { current, line in
            let size = (line as NSString).size(withAttributes: [.font: font])
            return max(current, ceil(size.width))
        }
        return min(maxWidth, max(28, measuredWidth + 14))
    }

    private func clipboardTextItem(_ item: ClipboardTextItem, width: CGFloat) -> some View {
        let isCopied = copiedTextItemID == item.id
        let textWidth = max(1, width - 12)
        let displayedText = item.attributedText ?? modernClipboardText(item.text)

        return ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .top, spacing: 0) {
                Text(displayedText)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: textWidth, alignment: .topLeading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(width: width, height: 54, alignment: .topLeading)

            if isCopied {
                copyBlinkIcon
                    .padding(4)
                    .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .background(isCopied ? Color.white.opacity(0.13) : Color.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCopied ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .white.opacity(isCopied ? 0.10 : 0), radius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            clipboard.copyTextToPasteboard(item)
            showCopiedText(item.id)
        }
        .animation(.easeOut(duration: 0.18), value: isCopied)
        .help(item.text)
        .onDrag {
            NSItemProvider(object: item.text as NSString)
        }
        .contextMenu {
            Button("Copy") {
                clipboard.copyTextToPasteboard(item)
                showCopiedText(item.id)
            }
            Button("Remove") {
                clipboard.recentTextItems.removeAll { $0.id == item.id }
            }
        }
    }

    private func clipboardImageItem(_ item: ClipboardImageItem) -> some View {
        let isCopied = copiedImageItemID == item.id

        return ZStack(alignment: .bottomTrailing) {
            ClipboardImageThumbnail(item: item)
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if isCopied {
                copyBlinkIcon
                    .padding(4)
                    .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCopied ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .white.opacity(isCopied ? 0.10 : 0), radius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            clipboard.copyImageToPasteboard(item)
            showCopiedImage(item.id)
        }
        .animation(.easeOut(duration: 0.18), value: isCopied)
        .help("Image clipboard item")
        .onDrag {
            NSItemProvider(item: item.data as NSData, typeIdentifier: item.typeIdentifier)
        }
        .contextMenu {
            Button("Copy") {
                clipboard.copyImageToPasteboard(item)
                showCopiedImage(item.id)
            }
            Button("Remove") {
                clipboard.recentImageItems.removeAll { $0.id == item.id }
            }
        }
    }

    private func showCopiedText(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            copiedTextItemID = id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard copiedTextItemID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedTextItemID = nil
            }
        }
    }

    private func showCopiedImage(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            copiedImageItemID = id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard copiedImageItemID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedImageItemID = nil
            }
        }
    }

    private var copyBlinkIcon: some View {
        Image(systemName: "doc.on.doc.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.black.opacity(0.82))
            .frame(width: 17, height: 17)
            .background(Color.white.opacity(0.88))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
    }

    private func modernClipboardText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = .system(size: 12, weight: .semibold, design: .rounded)
        attributed.foregroundColor = .white.opacity(0.88)
        return attributed
    }

    private var cameraPage: some View {
        let previewSize = cameraPreviewSize
        let previewCornerRadius = cameraPreviewCornerRadius

        return ZStack {
            HStack(spacing: cameraSideControlGap) {
                cameraUtilityStack
                cameraPreviewSurface(size: previewSize, cornerRadius: previewCornerRadius)
                cameraCaptureStack
            }
            .frame(maxWidth: .infinity, alignment: .center)

            cameraCaptureTray
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: cameraPreviewRowHeight)
        .frame(maxWidth: .infinity)
        .background(
            CameraSpaceShortcutView(manager: camera, aspectRatio: cameraCaptureAspectRatio)
                .frame(width: 0, height: 0)
        )
        .onChange(of: camera.captures.map(\.id)) { oldIDs, newIDs in
            guard let newestID = newIDs.first,
                  oldIDs.contains(newestID) == false,
                  newIDs.count >= oldIDs.count else {
                return
            }

            triggerCameraCaptureFlash()
        }
    }

    private func cameraPreviewSurface(size: CGSize, cornerRadius: CGFloat) -> some View {
        CameraPreviewView(manager: camera)
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: -1, y: 1, anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(cameraPreviewEffects(cornerRadius: cornerRadius))
            .overlay(cameraOpeningOverlay(size: size, cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.36), radius: 12, y: 5)
            .animation(.snappy(duration: 0.24, extraBounce: 0.03), value: isCameraPreviewExpanded)
    }

    @ViewBuilder
    private func cameraOpeningOverlay(size: CGSize, cornerRadius: CGFloat) -> some View {
        if isCameraOpening {
            ZStack {
                Color.black.opacity(0.78)

                if cameraStallHintVisible {
                    Text("No image — the camera may be covered or the room is too dark.")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .transition(.opacity)
                } else {
                    ShutterAnimationView()
                        .frame(
                            width: min(size.width, size.height) * 0.58,
                            height: min(size.width, size.height) * 0.58
                        )
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
            .allowsHitTesting(false)
        } else if let message = camera.previewErrorMessage, currentPage == .camera {
            ZStack {
                Color.black.opacity(0.82)

                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
        }
    }

    private var cameraUtilityStack: some View {
        VStack(spacing: 6) {
            cameraActionButton(
                systemName: "slider.horizontal.3",
                isActive: cameraPortraitEnabled || cameraStudioLightEnabled || cameraEdgeLightEnabled,
                tint: .green,
                size: cameraUtilityButtonSize
            ) {
                showCameraVideoEffectsPanel()
            }

            cameraActionButton(
                systemName: "arrow.triangle.2.circlepath",
                isActive: false,
                tint: .white,
                size: cameraUtilityButtonSize
            ) {
                camera.switchCamera()
            }

            cameraResizeButton {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                    isCameraPreviewExpanded.toggle()
                }
            }
        }
    }

    private var cameraCaptureStack: some View {
        VStack(spacing: 0) {
            cameraRecordButton(
                onPressStart: beginCameraShutterPress,
                onPressEnd: endCameraShutterPress
            )
        }
    }

    @ViewBuilder
    private func cameraPreviewEffects(cornerRadius: CGFloat) -> some View {
        ZStack {
            if camera.isRecording {
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { context in
                    cameraPreviewEffectLayer(
                        cornerRadius: cornerRadius,
                        pulse: cameraRecordingPulseAmount(at: context.date)
                    )
                }
            } else {
                cameraPreviewEffectLayer(cornerRadius: cornerRadius, pulse: 0)
            }

            cameraSystemEffectFrame(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    private func cameraSystemEffectFrame(cornerRadius: CGFloat) -> some View {
        if cameraPortraitEnabled {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.green.opacity(0.42), lineWidth: 1.4)
                .shadow(color: .green.opacity(0.22), radius: 8)
        }

        if cameraStudioLightEnabled {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.07),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 4,
                        endRadius: 150
                    )
                )
                .blendMode(.screen)
        }

        if cameraEdgeLightEnabled {
            TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { context in
                let pulse = 0.72 + cameraRecordingPulseAmount(at: context.date) * 0.22

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.green.opacity(0.95),
                                Color.cyan.opacity(0.80),
                                Color.white.opacity(0.88),
                                Color.green.opacity(0.95)
                            ],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .blur(radius: 2.2)
                    .opacity(pulse)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
    }

    private func cameraPreviewEffectLayer(cornerRadius: CGFloat, pulse: Double) -> some View {
        let baseColor = camera.isRecording
            ? Color.red.opacity(0.46 + pulse * 0.40)
            : Color.white.opacity(cameraCaptureFlash ? 0.95 : 0.18)
        let baseLineWidth = camera.isRecording
            ? CGFloat(1.8 + pulse * 1.0)
            : CGFloat(cameraCaptureFlash ? 2.5 : 1.0)

        return ZStack {
            if camera.isRecording {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.red.opacity(0.24 + pulse * 0.34), lineWidth: 7)
                    .blur(radius: 4)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(baseColor, lineWidth: baseLineWidth)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(cameraCaptureFlash ? 0.80 : 0), lineWidth: 5)
                .blur(radius: 2)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(cameraCaptureFlash ? 0.16 : 0))
        }
    }

    private func cameraRecordingPulseAmount(at date: Date) -> Double {
        let period = 1.12
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return (sin(progress * Double.pi * 2 - Double.pi / 2) + 1) / 2
    }

    private func triggerCameraCaptureFlash() {
        cameraCaptureFlashToken += 1
        let token = cameraCaptureFlashToken

        withAnimation(.easeOut(duration: 0.04)) {
            cameraCaptureFlash = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard token == cameraCaptureFlashToken else { return }

            withAnimation(.easeOut(duration: 0.28)) {
                cameraCaptureFlash = false
            }
        }
    }

    private var cameraCaptureTray: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    if camera.captures.isEmpty {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.40))
                            )
                            .frame(width: 34, height: 34)
                    }

                    ForEach(Array(camera.captures.reversed())) { item in
                        cameraCaptureItemView(item)
                            .onDrag {
                                NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
                            }
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(Self.cameraTrayBottomAnchor)
                }
                .frame(minHeight: cameraPreviewRowHeight - 12, alignment: .bottom)
                .padding(6)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: camera.captures.first?.id) { _, newestID in
                guard newestID != nil else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(Self.cameraTrayBottomAnchor, anchor: .bottom)
                }
            }
        }
        .frame(width: 46, height: cameraPreviewRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func cameraCaptureItemView(_ item: CameraCaptureItem) -> some View {
        let isCopied = copiedCameraCaptureID == item.id

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))

            CameraCaptureThumbnail(item: item)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if isCopied {
                copyBlinkIcon
                    .padding(2)
                    .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                Image(systemName: item.kind == .photo ? "photo.fill" : "play.fill")
                    .font(.system(size: item.kind == .photo ? 7 : 6, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .background(Color.black.opacity(0.50))
                    .clipShape(Circle())
                    .padding(2)
            }
        }
        .frame(width: 34, height: 34)
        .background(isCopied ? Color.white.opacity(0.13) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCopied ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            if hoveredCameraCaptureID == item.id {
                Button {
                    camera.deleteCapture(item)
                    if copiedCameraCaptureID == item.id {
                        copiedCameraCaptureID = nil
                    }
                    hoveredCameraCaptureID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.82))
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(0.90))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .padding(2)
                .transition(.scale(scale: 0.82, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .shadow(color: .white.opacity(isCopied ? 0.10 : 0), radius: 8)
        .animation(.easeOut(duration: 0.18), value: isCopied)
        .animation(.easeOut(duration: 0.14), value: hoveredCameraCaptureID == item.id)
        .help(item.displayName)
        .onHover { hovering in
            if hovering {
                hoveredCameraCaptureID = item.id
            } else if hoveredCameraCaptureID == item.id {
                hoveredCameraCaptureID = nil
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .onTapGesture(count: 1) {
            ClipboardManager.shared.copyFileToPasteboard(ShelfItem(url: item.url))
            showCopiedCameraCapture(item.id)
        }
    }

    private func showCopiedCameraCapture(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            copiedCameraCaptureID = id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard copiedCameraCaptureID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedCameraCaptureID = nil
            }
        }
    }

    private func showCameraVideoEffectsPanel() {
        if #available(macOS 12.0, *) {
            AVCaptureDevice.showSystemUserInterface(.videoEffects)
        } else {
            showMediaActionMessage(String(localized: "Video effects unavailable", comment: "Shown when camera video effects cannot be applied."))
        }
    }

    private func syncCameraSystemEffects() {
        if #available(macOS 12.0, *) {
            cameraPortraitEnabled = AVCaptureDevice.isPortraitEffectEnabled
        }

        if #available(macOS 13.0, *) {
            cameraStudioLightEnabled = AVCaptureDevice.isStudioLightEnabled
        }

        if #available(macOS 26.2, *) {
            cameraEdgeLightEnabled = AVCaptureDevice.isEdgeLightEnabled || AVCaptureDevice.isEdgeLightActive
        }
    }

    private func takeCameraPhotoWithCurrentOptions() {
        if cameraStudioLightEnabled || cameraEdgeLightEnabled {
            triggerCameraCaptureFlash()
        }
        camera.takePhoto(aspectRatio: cameraCaptureAspectRatio)
    }

    private func beginCameraShutterPress() {
        guard cameraRecordPressActive == false else { return }

        cameraRecordPressActive = true
        cameraRecordPressStartedRecording = false
        cameraRecordPressToken += 1
        let token = cameraRecordPressToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard cameraRecordPressActive, cameraRecordPressToken == token else { return }
            cameraRecordPressStartedRecording = true
            camera.startRecording(aspectRatio: cameraCaptureAspectRatio)
        }
    }

    private func endCameraShutterPress() {
        guard cameraRecordPressActive else { return }

        let shouldStopRecording = cameraRecordPressStartedRecording
        cameraRecordPressActive = false
        cameraRecordPressStartedRecording = false
        cameraRecordPressToken += 1

        if shouldStopRecording {
            camera.stopRecording()
        } else {
            takeCameraPhotoWithCurrentOptions()
        }
    }

    private func cameraActionButton(
        systemName: String,
        isActive: Bool,
        tint: Color = .white,
        size: CGFloat = 34,
        action: @escaping () -> Void
    ) -> some View {
        cameraControlButton(isActive: isActive, tint: tint, size: size, icon: {
            Image(systemName: systemName)
                .font(.system(size: max(10, size * 0.36), weight: .bold))
        }, action: action)
    }

    private func cameraResizeButton(action: @escaping () -> Void) -> some View {
        cameraControlButton(
            isActive: isCameraPreviewExpanded,
            tint: .white,
            size: cameraUtilityButtonSize,
            icon: {
                Image(systemName: isCameraPreviewExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: max(10, cameraUtilityButtonSize * 0.38), weight: .bold))
                    .rotationEffect(.degrees(-45))
            },
            action: action
        )
    }

    private func cameraRecordButton(
        onPressStart: @escaping () -> Void,
        onPressEnd: @escaping () -> Void
    ) -> some View {
        let isPressed = cameraRecordPressActive || camera.isRecording
        let ringSize = cameraCaptureButtonSize * 0.82

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(isPressed ? 0.98 : 0.82), lineWidth: 2)
                .frame(width: ringSize, height: ringSize)

            Circle()
                .fill(Color.white.opacity(isPressed ? 0.98 : 0.92))
                .frame(
                    width: ringSize * (isPressed ? 0.70 : 0.62),
                    height: ringSize * (isPressed ? 0.70 : 0.62)
                )
        }
        .frame(width: cameraCaptureButtonSize, height: cameraCaptureButtonSize)
        .scaleEffect(isPressed ? 0.96 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onPressStart()
                }
                .onEnded { _ in
                    onPressEnd()
                }
        )
        .animation(.easeOut(duration: 0.14), value: isPressed)
    }

    private func cameraControlButton<Icon: View>(
        isActive: Bool,
        tint: Color,
        size: CGFloat,
        @ViewBuilder icon: @escaping () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon()
                .foregroundColor(isActive ? tint.opacity(0.98) : .white.opacity(0.92))
                .frame(width: size, height: size)
                .background(
                    LinearGradient(
                        colors: [
                            tint.opacity(isActive ? 0.24 : 0.16),
                            Color.white.opacity(isActive ? 0.10 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(tint.opacity(isActive ? 0.30 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func mediaButton(systemName: String, size: CGFloat = 30, fontSize: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(mediaButtonHelp(for: systemName))
    }

    private func mediaButtonHelp(for systemName: String) -> String {
        switch systemName {
        case "backward.fill":
            return String(localized: "Previous track", comment: "Tooltip for the previous track button.")
        case "forward.fill":
            return String(localized: "Next track", comment: "Tooltip for the next track button.")
        case "pause.fill", "play.fill":
            return String(localized: "Play / pause", comment: "Tooltip for the play/pause button.")
        default:
            return String(localized: "Media control", comment: "Generic tooltip for a media control button.")
        }
    }

    @ViewBuilder
    private var mediaInfoArea: some View {
        let isShowingLyrics = mediaInlinePanel == .lyrics

        ZStack(alignment: .leading) {
            mediaSongInfoCard
                .opacity(isShowingLyrics ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isShowingLyrics ? -88 * Double(mediaInfoFlipDirection) : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: mediaInfoFlipDirection > 0 ? .top : .bottom,
                    perspective: 0.72
                )
                .offset(y: isShowingLyrics ? -4 * mediaInfoFlipDirection : 0)
                .allowsHitTesting(isShowingLyrics == false)

            mediaLyricsInfoCard
                .opacity(isShowingLyrics ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isShowingLyrics ? 0 : 88 * Double(mediaInfoFlipDirection)),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: mediaInfoFlipDirection > 0 ? .bottom : .top,
                    perspective: 0.72
                )
                .offset(y: isShowingLyrics ? 0 : 4 * mediaInfoFlipDirection)
                .allowsHitTesting(isShowingLyrics)
        }
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .clipped()
    }

    private var mediaDisplayTitle: String {
        let title = nowPlaying.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "Not playing" {
            return String(localized: "Not playing", comment: "Media player title shown when nothing is playing.")
        }
        return nowPlaying.title
    }

    private var mediaSongInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(mediaDisplayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                mediaActionStrip
            }

            HStack(spacing: 6) {
                Text(nowPlaying.artist.isEmpty ? nowPlaying.sourceName : nowPlaying.artist)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if nowPlaying.isPlaying {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
    }

    private var mediaLyricsInfoCard: some View {
        let lyricsWindow = visibleLyricsWindow

        return Group {
            if isLyricsLoading(lyricsWindow) {
                LyricsSkeletonShimmer()
            } else if let unavailableMessage = unavailableLyricsMessage(for: lyricsWindow) {
                mediaLyricsUnavailableMessage(unavailableMessage)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    mediaLyricsLine(lyricsWindow.previous, role: .previous)
                    mediaLyricsLine(lyricsWindow.current, role: .current)
                    mediaLyricsLine(lyricsWindow.next, role: .next)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .clipped()
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24), value: lyricsWindow)
    }

    private var visibleLyricsWindow: InlineLyricsWindow {
        if mediaLyricsWindow.current.isEmpty == false {
            return mediaLyricsWindow
        }

        let text = mediaLyricsText.isEmpty ? nowPlaying.inlineLyricsText() : mediaLyricsText
        return InlineLyricsWindow(previous: nil, current: text, next: nil)
    }

    private func isLyricsLoading(_ lyricsWindow: InlineLyricsWindow) -> Bool {
        lyricsWindow.current.trimmingCharacters(in: .whitespacesAndNewlines) == "Loading lyrics..."
    }

    private func unavailableLyricsMessage(for lyricsWindow: InlineLyricsWindow) -> String? {
        let current = lyricsWindow.current.trimmingCharacters(in: .whitespacesAndNewlines)

        if current == "Lyrics not found" {
            return "Lyrics unavailable for this track"
        }

        if current == "No song playing" || current == "Not playing" {
            return String(localized: "No song playing", comment: "Media lyrics message shown when nothing is playing.")
        }

        if current.hasPrefix("Lyrics are not exposed locally") {
            return "Lyrics unavailable for this source"
        }

        return nil
    }

    private func mediaLyricsUnavailableMessage(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.40))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 10.6, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("No synced line is available right now")
                    .font(.system(size: 8.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }

    private enum MediaLyricsLineRole: Equatable {
        case previous
        case current
        case next
    }

    @ViewBuilder
    private func mediaLyricsLine(_ text: String?, role: MediaLyricsLineRole) -> some View {
        let lineText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = lineText.isEmpty

        if role == .current, isPlaceholder == false {
            LoopingLyricText(
                text: lineText,
                font: mediaLyricsLineFont(role),
                color: mediaLyricsLineColor(role)
            )
            .id("\(role)-\(lineText)")
            .transition(mediaLyricsLineTransition(for: role))
            .frame(
                maxWidth: .infinity,
                minHeight: mediaLyricsLineHeight(role),
                maxHeight: mediaLyricsLineHeight(role),
                alignment: .leading
            )
        } else {
            Text(isPlaceholder ? " " : lineText)
                .font(mediaLyricsLineFont(role))
                .foregroundColor(mediaLyricsLineColor(role).opacity(isPlaceholder ? 0 : 1))
                .lineLimit(1)
                .truncationMode(.tail)
                .id("\(role)-\(lineText)")
                .transition(mediaLyricsLineTransition(for: role))
                .frame(
                    maxWidth: .infinity,
                    minHeight: mediaLyricsLineHeight(role),
                    maxHeight: mediaLyricsLineHeight(role),
                    alignment: .leading
                )
        }
    }

    private func mediaLyricsLineTransition(for role: MediaLyricsLineRole) -> AnyTransition {
        let insertionEdge: Edge = role == .previous ? .top : .bottom
        let removalEdge: Edge = role == .next ? .bottom : .top
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func mediaLyricsLineFont(_ role: MediaLyricsLineRole) -> Font {
        switch role {
        case .previous:
            return .system(size: 9.2, weight: .bold, design: .rounded)
        case .current:
            return .system(size: 11.2, weight: .bold, design: .rounded)
        case .next:
            return .system(size: 9.8, weight: .bold, design: .rounded)
        }
    }

    private func mediaLyricsLineColor(_ role: MediaLyricsLineRole) -> Color {
        switch role {
        case .previous:
            return .white.opacity(0.28)
        case .current:
            return .white.opacity(0.92)
        case .next:
            return .white.opacity(0.58)
        }
    }

    private func mediaLyricsLineHeight(_ role: MediaLyricsLineRole) -> CGFloat {
        switch role {
        case .previous:
            return 12
        case .current:
            return 15
        case .next:
            return 13
        }
    }

    private var mediaActionStrip: some View {
        HStack(spacing: 5) {
            mediaActionButton(
                systemName: "quote.bubble.fill",
                help: String(localized: "Show lyrics", comment: "Tooltip for the show lyrics button."),
                isActive: mediaInlinePanel == .lyrics
            ) {
                toggleMediaInlinePanel(.lyrics)
            }

            mediaShareButton

            mediaVolumeControl
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // Other active media sessions, listed under the main player the way the
    // macOS menu bar Now Playing item stacks multiple players.
    private var extraMediaSources: [MediaSourceInfo] {
        let activeID = nowPlaying.selectedSourceID ?? "system"
        return nowPlaying.availableSources.filter { $0.id != activeID }
    }

    private static let mediaSourceRowHeight: CGFloat = 34
    private static let mediaSourceRowSpacing: CGFloat = 5

    private var mediaSourceListHeight: CGFloat {
        let count = CGFloat(extraMediaSources.count)
        guard count > 0 else { return 0 }
        return count * (Self.mediaSourceRowHeight + Self.mediaSourceRowSpacing) + 3
    }

    private var mediaSourceList: some View {
        VStack(spacing: Self.mediaSourceRowSpacing) {
            ForEach(extraMediaSources) { source in
                mediaSourceRow(source)
            }
        }
        .padding(.top, 3)
    }

    private func mediaSourceRow(_ source: MediaSourceInfo) -> some View {
        HStack(spacing: 8) {
            Group {
                if let image = nowPlaying.sourceArtworks[source.id] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.08))
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(source.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            mediaButton(systemName: source.isPlaying ? "pause.fill" : "play.fill") {
                nowPlaying.togglePlayPause(sourceID: source.id)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: Self.mediaSourceRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            nowPlaying.selectSource(source.id)
        }
    }

    private var mediaShareButton: some View {
        mediaActionButton(systemName: "square.and.arrow.up", help: String(localized: "Share song", comment: "Tooltip for the share song button.")) {
            ui.isInteractionHeld = true
            pendingMediaSharePayload = MediaSharePayload(items: nowPlaying.currentTrackShareItems())
        }
        .background(
            MediaShareSheetPresenter(payload: $pendingMediaSharePayload)
                .frame(width: 1, height: 1)
        )
    }

    @ViewBuilder
    private var mediaVolumeControl: some View {
        let isExpanded = isOutputVolumeHovered || isOutputVolumeScrubbing

        HStack(spacing: 4) {
            mediaActionButton(systemName: outputVolumeIconName, help: String(localized: "Sound (M)", comment: "Tooltip for the mute toggle button; M is the keyboard shortcut letter.")) {
                toggleOutputMute()
            }

            if isExpanded {
                Slider(
                    value: Binding(
                        get: { outputVolumeLevel },
                        set: { setOutputVolumeLevel($0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isOutputVolumeScrubbing = editing
                        if editing == false {
                            refreshOutputVolumeLevel()
                        }
                    }
                )
                .tint(.white.opacity(0.82))
                .controlSize(.mini)
                .frame(width: 54)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
            }
        }
        .padding(.trailing, isExpanded ? 2 : 0)
        .frame(height: 21)
        .animation(.easeOut(duration: 0.16), value: isExpanded)
        .onHover { hovering in
            if hovering {
                refreshOutputVolumeLevel()
            }
            isOutputVolumeHovered = hovering
        }
        .help("Sound volume")
    }

    private var outputVolumeIconName: String {
        if isOutputMuted || outputVolumeLevel <= 0.01 {
            return "speaker.slash.fill"
        }

        if outputVolumeLevel < 0.38 {
            return "speaker.wave.1.fill"
        }

        if outputVolumeLevel < 0.72 {
            return "speaker.wave.2.fill"
        }

        return "speaker.wave.3.fill"
    }

    private func refreshOutputVolumeLevel() {
        let state = nowPlaying.currentOutputVolumeState()
        outputVolumeLevel = state.level
        isOutputMuted = state.isMuted
        if state.level > 0.01 {
            lastAudibleVolumeLevel = outputVolumeLevel
        }
    }

    private func setOutputVolumeLevel(_ level: Double) {
        let clampedLevel = min(1, max(0, level))
        outputVolumeLevel = clampedLevel
        isOutputMuted = false
        if clampedLevel > 0.01 {
            lastAudibleVolumeLevel = clampedLevel
        }
        nowPlaying.setOutputVolumeLevel(clampedLevel)
    }

    private func toggleOutputMute() {
        if isOutputMuted || outputVolumeLevel <= 0.01 {
            let restoredLevel = max(0.18, lastAudibleVolumeLevel)
            outputVolumeLevel = restoredLevel
            isOutputMuted = false
            nowPlaying.setOutputVolumeLevel(restoredLevel)
            nowPlaying.setOutputMuted(false)
        } else {
            isOutputMuted = true
            nowPlaying.setOutputMuted(true)
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard ui.isExpanded,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }

        if MonotchShortcutKey.matches(previousTabShortcut, event: event) {
            switchTabByKeyboard(direction: -1)
            return true
        }

        if MonotchShortcutKey.matches(nextTabShortcut, event: event) {
            switchTabByKeyboard(direction: 1)
            return true
        }

        if currentPage == .multimedia,
           MonotchShortcutKey.matches(toggleLyricsShortcut, event: event) {
            toggleMediaInlinePanel(.lyrics)
            return true
        }

        return false
    }

    private func switchTabByKeyboard(direction: Int) {
        guard activePages.isEmpty == false else { return }
        guard isKeyboardTabSwitchLocked == false else { return }

        isKeyboardTabSwitchLocked = true
        switchToPageIndex(currentPageIndex + direction, direction: direction)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isKeyboardTabSwitchLocked = false
        }
    }

    private func mediaActionButton(
        systemName: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white.opacity(isActive ? 0.95 : 0.78))
                .frame(width: 19, height: 19)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.22 : 0.12),
                            Color.white.opacity(isActive ? 0.10 : 0.055)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isActive ? 0.20 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var mediaBottomArea: some View {
        progressSlider
    }

    private var mediaQueuePanel: some View {
        let items = mediaQueueItems.isEmpty ? nowPlaying.inlineQueueItems() : mediaQueueItems

        return mediaInlinePanelContainer(systemName: "list.bullet") {
            HStack(spacing: 7) {
                ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { item in
                    Text(item.offset == 0 ? "Now: \(item.element)" : item.element)
                        .font(.system(size: 8.8, weight: item.offset == 0 ? .semibold : .medium, design: .rounded))
                        .foregroundColor(.white.opacity(item.offset == 0 ? 0.82 : 0.46))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
                mediaInlineCloseButton
            }
        }
    }

    private var mediaLyricsPanel: some View {
        mediaInlinePanelContainer(systemName: "quote.bubble.fill") {
            HStack(spacing: 7) {
                Text(mediaLyricsText.isEmpty ? nowPlaying.inlineLyricsText() : mediaLyricsText)
                    .font(.system(size: 8.8, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
                mediaInlineCloseButton
            }
        }
    }

    private func mediaInlineMessage(_ message: String, systemName: String) -> some View {
        mediaInlinePanelContainer(systemName: systemName) {
            HStack(spacing: 7) {
                Text(message)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.80))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
        }
    }

    private func mediaInlinePanelContainer<Content: View>(
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white.opacity(0.60))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.075))
                .clipShape(Circle())

            content()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 25, maxHeight: 25)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var mediaInlineCloseButton: some View {
        Button {
            showSongInfoInMediaInfo()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    private func toggleMediaInlinePanel(_ panel: MediaInlinePanel) {
        if panel == .lyrics {
            if mediaInlinePanel == .lyrics {
                mediaInfoFlipDirection = -1
                showSongInfoInMediaInfo()
            } else {
                mediaInfoFlipDirection = 1
                showLyricsInMediaInfo()
            }
            return
        }

        if panel == .queue, mediaInlinePanel != .queue {
            withAnimation(.easeOut(duration: 0.14)) {
                mediaActionMessage = nil
                mediaQueueItems = ["Loading Spotify queue..."]
                mediaInlinePanel = .queue
            }

            nowPlaying.loadInlineQueueItems { items in
                withAnimation(.easeOut(duration: 0.14)) {
                    guard mediaInlinePanel == .queue else { return }
                    mediaQueueItems = items
                }
            }
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            mediaActionMessage = nil
            if mediaInlinePanel == panel {
                mediaInlinePanel = nil
            } else {
                mediaQueueItems = ["Loading Spotify queue..."]
                mediaInlinePanel = panel
            }
        }
    }

    private func showLyricsInMediaInfo() {
        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26)) {
            mediaActionMessage = nil
            mediaLyricsText = "Loading lyrics..."
            mediaLyricsWindow = InlineLyricsWindow(previous: nil, current: "Loading lyrics...", next: nil)
            mediaInlinePanel = .lyrics
            mediaLyricsTrackKey = currentMediaTrackKey
        }

        loadMediaLyrics()
    }

    private func showSongInfoInMediaInfo() {
        mediaLyricsRequestToken += 1
        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.26)) {
            mediaInlinePanel = nil
        }
    }

    private func loadMediaLyrics() {
        let trackKey = currentMediaTrackKey
        mediaLyricsTrackKey = trackKey
        mediaLyricsRequestToken += 1
        let requestToken = mediaLyricsRequestToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 12.8) {
            guard requestToken == mediaLyricsRequestToken,
                  mediaInlinePanel == .lyrics,
                  currentMediaTrackKey == trackKey,
                  isLyricsLoading(mediaLyricsWindow) else {
                return
            }

            withAnimation(.easeOut(duration: 0.14)) {
                updateMediaLyricsWindow(InlineLyricsWindow(previous: nil, current: "Lyrics not found", next: nil))
            }
        }

        nowPlaying.loadInlineLyricsWindow { lyricsWindow in
            DispatchQueue.main.async {
                guard requestToken == mediaLyricsRequestToken,
                      mediaInlinePanel == .lyrics,
                      currentMediaTrackKey == trackKey else {
                    return
                }

                withAnimation(.easeOut(duration: 0.14)) {
                    updateMediaLyricsWindow(lyricsWindow)
                }
            }
        }
    }

    private func reloadLyricsIfNeeded() {
        guard mediaInlinePanel == .lyrics else { return }
        let trackKey = currentMediaTrackKey
        guard trackKey != mediaLyricsTrackKey else { return }

        mediaLyricsTrackKey = trackKey
        mediaLyricsText = "Loading lyrics..."
        mediaLyricsWindow = InlineLyricsWindow(previous: nil, current: "Loading lyrics...", next: nil)
        loadMediaLyrics()
    }

    private func refreshVisibleLyricsLine() {
        guard mediaInlinePanel == .lyrics,
              mediaLyricsText != "Loading lyrics...",
              mediaLyricsText != "Lyrics not found",
              mediaLyricsText != "No song playing" else {
            return
        }

        let updatedLyricsWindow = nowPlaying.inlineLyricsWindow()
        guard updatedLyricsWindow.current.hasPrefix("Lyrics are not exposed locally") == false,
              updatedLyricsWindow != mediaLyricsWindow else {
            return
        }

        updateMediaLyricsWindow(updatedLyricsWindow)
    }

    private func updateMediaLyricsWindow(_ lyricsWindow: InlineLyricsWindow) {
        mediaLyricsText = lyricsWindow.current
        mediaLyricsWindow = lyricsWindow
    }

    private func showMediaActionMessage(_ message: String) {
        mediaActionMessageToken += 1
        let token = mediaActionMessageToken

        withAnimation(.easeOut(duration: 0.14)) {
            mediaInlinePanel = nil
            mediaActionMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard mediaActionMessageToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                mediaActionMessage = nil
            }
        }
    }

    @ViewBuilder
    private var progressSlider: some View {
        let duration = max(nowPlaying.duration, 1)
        let progress = nowPlaying.duration > 0
            ? min(1, max(0, sliderValue / duration))
            : 0
        let isInteractive = nowPlaying.duration > 0
        let isThumbVisible = isProgressSliderHovered || isScrubbing

        VStack(spacing: 2) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let thumbSize: CGFloat = 12
                let thumbX = CGFloat(progress) * width
                let bubbleWidth: CGFloat = 48
                let bubbleValue = isScrubbing ? sliderValue : progressSliderHoverValue
                let bubbleProgress = duration > 0
                    ? min(1, max(0, bubbleValue / duration))
                    : 0
                let bubbleTrackX = CGFloat(bubbleProgress) * width
                let bubbleX = width <= bubbleWidth
                    ? width / 2
                    : min(max(bubbleTrackX, bubbleWidth / 2), width - bubbleWidth / 2)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: width, height: 4)

                    Capsule()
                        .fill(Color.white.opacity(isInteractive ? 0.90 : 0.30))
                        .frame(width: max(0, thumbX), height: 4)

                    Circle()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .offset(x: thumbX - thumbSize / 2)
                        .opacity(isThumbVisible && isInteractive ? 1 : 0)

                    if isThumbVisible && isInteractive {
                        Text(formatTime(bubbleValue))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: bubbleWidth, height: 24)
                            .background(Color.black.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .offset(x: bubbleX - bubbleWidth / 2, y: 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                .frame(width: width, height: 16, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isInteractive else { return }
                            isScrubbing = true
                            let draggedValue = progressSliderValue(at: value.location.x, width: width, duration: duration)
                            sliderValue = draggedValue
                            progressSliderHoverValue = draggedValue
                        }
                        .onEnded { value in
                            guard isInteractive else { return }
                            sliderValue = progressSliderValue(at: value.location.x, width: width, duration: duration)
                            nowPlaying.seek(to: sliderValue)
                            isScrubbing = false
                        }
                )
                .onContinuousHover(coordinateSpace: .local) { phase in
                    guard isInteractive else { return }

                    switch phase {
                    case let .active(location):
                        progressSliderHoverValue = progressSliderValue(
                            at: location.x,
                            width: width,
                            duration: duration
                        )
                        if isProgressSliderHovered == false {
                            withAnimation(.easeOut(duration: 0.12)) {
                                isProgressSliderHovered = true
                            }
                        }
                    case .ended:
                        withAnimation(.easeOut(duration: 0.12)) {
                            isProgressSliderHovered = false
                        }
                    }
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.12), value: isThumbVisible)

            HStack {
                Text(formatTime(sliderValue))
                Spacer()
                Text(formatTime(nowPlaying.duration))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.48))
            .padding(.horizontal, 4)
        }
    }

    private func progressSliderValue(at xPosition: CGFloat, width: CGFloat, duration: Double) -> Double {
        let progress = min(1, max(0, Double(xPosition / max(width, 1))))
        return progress * duration
    }

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            } else {
                Image(systemName: nowPlaying.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let seconds = Int(value.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func precisePercentText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let percentage = max(0, value * 100)
        let formatted = formatter.string(from: NSNumber(value: percentage)) ?? String(format: "%.2f", percentage)
        return "\(formatted)%"
    }

    private func countText(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func byteText(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: Int64(value))
    }

    private func memoryText(_ value: UInt64) -> String {
        let gibibyte = 1_073_741_824.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        let amount = Double(value) / gibibyte
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(formatted) GB"
    }

    private func byteNumberText(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        formatter.includesUnit = false
        formatter.includesCount = true
        return formatter.string(fromByteCount: Int64(value))
    }

    private func rpmText(_ value: Double) -> String {
        guard value > 0 else { return "0 rpm" }
        return "\(Int(value.rounded())) rpm"
    }

    private func systemProgressTint(_ progress: Double) -> Color {
        if progress >= 0.82 {
            return Color(red: 1.00, green: 0.38, blue: 0.30).opacity(0.88)
        }

        if progress >= 0.60 {
            return Color(red: 1.00, green: 0.68, blue: 0.24).opacity(0.90)
        }

        return Color(red: 0.32, green: 0.78, blue: 0.55).opacity(0.92)
    }
}

private extension SystemMonitorManager {
    var memoryTotal: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    var memoryProgress: Double {
        let total = memoryTotal
        guard total > 0 else { return 0 }
        return Double(memoryUsed) / Double(total)
    }

    var diskProgress: Double {
        let total = diskUsed + diskFree
        guard total > 0 else { return 0 }
        return Double(diskUsed) / Double(total)
    }

    var fanStatusText: String {
        if fanAvailable == false {
            return String(localized: "No hardware fan", comment: "Fan status when the Mac has no hardware fan.")
        }

        if fanAccessDenied {
            return String(localized: "SMC fan keys locked", comment: "Fan status when SMC fan keys are locked.")
        }

        if fanHelperRequiresApproval {
            return String(localized: "Approve fan helper", comment: "Fan status prompting the user to approve the fan helper.")
        }

        if fanWriteAccessDenied {
            return String(localized: "Fan write blocked", comment: "Fan status when writing fan speed is blocked.")
        }

        if fanLastWriteFailed {
            return String(localized: "Fan write failed", comment: "Fan status when the last fan speed write failed.")
        }

        if fanControlAvailable {
            switch fanMode {
            case .automatic:
                return String(localized: "Automatic", comment: "Fan status for automatic mode.")
            case .silent:
                return String(localized: "Manual silent", comment: "Fan status for manual silent mode.")
            case .balanced:
                return String(localized: "Manual balanced", comment: "Fan status for manual balanced mode.")
            case .performance:
                return String(localized: "Manual performance", comment: "Fan status for manual performance mode.")
            case .maximum:
                return String(localized: "Manual max", comment: "Fan status for manual maximum mode.")
            }
        }

        return String(localized: "SMC fan keys unavailable", comment: "Fan status when SMC fan keys are unavailable.")
    }
}

private extension SystemMonitorManager.TemperatureReading.Kind {
    var temperatureTitle: String {
        switch self {
        case .cpu: return String(localized: "CPU", comment: "The CPU temperature sensor.")
        case .gpu: return String(localized: "GPU", comment: "The GPU temperature sensor.")
        case .ssd: return String(localized: "SSD", comment: "The SSD temperature sensor.")
        case .battery: return String(localized: "Battery", comment: "The battery temperature sensor.")
        case .memory: return String(localized: "Memory Bank", comment: "The memory bank temperature sensor.")
        case .wifi: return String(localized: "Wi-Fi", comment: "The Wi-Fi temperature sensor.")
        }
    }
}

private extension SystemMonitorManager.StorageCategory.Kind {
    var storageTitle: String {
        switch self {
        case .photos: return String(localized: "Photos", comment: "The Photos storage category.")
        case .applications: return String(localized: "Apps", comment: "The Apps storage category.")
        case .documents: return String(localized: "Documents", comment: "The Documents storage category.")
        case .developer: return String(localized: "Developer", comment: "The Developer storage category.")
        case .mail: return String(localized: "Mail", comment: "The Mail storage category.")
        case .systemData: return String(localized: "System Data", comment: "The System Data storage category.")
        }
    }

    var storageColor: Color {
        switch self {
        case .photos: return Color(red: 1.00, green: 0.34, blue: 0.34)
        case .applications: return Color(red: 1.00, green: 0.63, blue: 0.23)
        case .documents: return Color(red: 1.00, green: 0.84, blue: 0.04)
        case .developer: return Color(red: 0.25, green: 0.82, blue: 0.43)
        case .mail: return Color(red: 0.05, green: 0.78, blue: 0.72)
        case .systemData: return Color.white.opacity(0.55)
        }
    }
}

private let systemDetailPanelFixedHeight: CGFloat = 120

private extension View {
    func systemDetailPanelStyle() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: systemDetailPanelFixedHeight, maxHeight: systemDetailPanelFixedHeight, alignment: .center)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.062), Color.white.opacity(0.034)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    func memoryDetailPanelStyle() -> some View {
        self.systemDetailPanelStyle()
    }
}

private struct ShutterAnimationView: View {
    @State private var openAmount: CGFloat = 0.16

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.22))

                ForEach(0..<7, id: \.self) { index in
                    ShutterBlade(openAmount: openAmount)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.34),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            ShutterBlade(openAmount: openAmount)
                                .stroke(Color.white.opacity(0.10), lineWidth: max(0.7, size * 0.006))
                        )
                        .rotationEffect(.degrees(Double(index) * 360.0 / 7.0))
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                }

                Circle()
                    .stroke(Color.white.opacity(0.24), lineWidth: max(1.0, size * 0.016))
                    .frame(
                        width: size * (0.22 + openAmount * 0.34),
                        height: size * (0.22 + openAmount * 0.34)
                    )

                Circle()
                    .fill(Color.black.opacity(0.42))
                    .frame(
                        width: size * (0.14 + openAmount * 0.24),
                        height: size * (0.14 + openAmount * 0.24)
                    )
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            openAmount = 0.16
            withAnimation(.easeInOut(duration: 0.86).repeatForever(autoreverses: true)) {
                openAmount = 0.82
            }
        }
    }
}

private struct ShutterBlade: Shape {
    var openAmount: CGFloat

    var animatableData: CGFloat {
        get { openAmount }
        set { openAmount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let clampedOpen = min(1, max(0, openAmount))
        let inner = size * (0.04 + clampedOpen * 0.22)
        let outer = size * 0.54
        let halfBlade = size * (0.16 - clampedOpen * 0.025)
        let skew = size * (0.13 + clampedOpen * 0.04)

        var path = Path()
        path.move(to: CGPoint(x: center.x + inner, y: center.y - halfBlade))
        path.addLine(to: CGPoint(x: center.x + outer, y: center.y - halfBlade - skew))
        path.addLine(to: CGPoint(x: center.x + outer, y: center.y + halfBlade + skew * 0.36))
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y + halfBlade))
        path.closeSubpath()
        return path
    }
}

private struct CameraCaptureThumbnail: View {
    let item: CameraCaptureItem

    @State private var image: NSImage?

    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind == .photo ? "photo" : "play.rectangle")
                    .font(.system(size: item.kind == .photo ? 15 : 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.46))
            }
        }
        .clipped()
        .task(id: item.url) {
            let key = item.url.standardizedFileURL as NSURL
            if let cachedImage = Self.cache.object(forKey: key) {
                image = cachedImage
                return
            }

            guard let loadedImage = loadThumbnail(for: item) else { return }
            Self.cache.setObject(loadedImage, forKey: key, cost: 120 * 120 * 4)
            image = loadedImage
        }
    }

    private func loadThumbnail(for item: CameraCaptureItem) -> NSImage? {
        switch item.kind {
        case .photo:
            return NSImage(contentsOf: item.url)
        case .movie:
            let asset = AVAsset(url: item.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 160)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.45, preferredTimescale: 600)

            let times = [
                CMTime(seconds: 0.28, preferredTimescale: 600),
                CMTime(seconds: 0.65, preferredTimescale: 600),
                CMTime(seconds: 1.0, preferredTimescale: 600),
                CMTime(seconds: 0.0, preferredTimescale: 600)
            ]
            var fallbackImage: NSImage?

            for time in times {
                guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
                let image = NSImage(cgImage: cgImage, size: .zero)
                if thumbnailImageHasVisiblePixels(cgImage) {
                    return image
                }
                fallbackImage = fallbackImage ?? image
            }

            return fallbackImage
        }
    }

    private func thumbnailImageHasVisiblePixels(_ image: CGImage) -> Bool {
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

private struct ClipboardImageThumbnail: View {
    let item: ClipboardImageItem

    @State private var image: NSImage?

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.48))
            }
        }
        .clipped()
        .task(id: item.id) {
            let key = item.id.uuidString as NSString
            if let cachedImage = Self.cache.object(forKey: key) {
                image = cachedImage
                return
            }

            guard let decodedImage = NSImage(data: item.data) else { return }
            Self.cache.setObject(decodedImage, forKey: key, cost: item.data.count)
            image = decodedImage
        }
    }
}

private struct FanRotorIcon: View {
    let fanID: Int
    let rpm: Double
    let tint: Color
    let size: CGFloat

    @State private var spinBaseAngle: Double = 0
    @State private var spinFromSpeed: Double = 0
    @State private var spinStartDate = Date()

    // How quickly the rotor approaches its target speed (1/s); ~0.6 s time constant.
    private static let spinResponse: Double = 1.6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            fanBlade(degrees: spinAngle(at: context.date))
        }
        .onAppear {
            spinFromSpeed = Self.speed(forRPM: rpm)
            spinStartDate = Date()
        }
        .onChange(of: rpm) { oldRPM, _ in
            let now = Date()
            let oldTarget = Self.speed(forRPM: oldRPM)
            let elapsed = max(0, now.timeIntervalSince(spinStartDate))
            let decay = exp(-Self.spinResponse * elapsed)

            spinBaseAngle = spinAngle(at: now, target: oldTarget)
            spinFromSpeed = oldTarget + (spinFromSpeed - oldTarget) * decay
            spinStartDate = now
        }
    }

    private static func speed(forRPM rpm: Double) -> Double {
        rpm > 20 ? min(5.0, max(0.35, rpm / 1500)) : 0
    }

    private func spinAngle(at date: Date, target: Double? = nil) -> Double {
        let target = target ?? Self.speed(forRPM: rpm)
        let elapsed = max(0, date.timeIntervalSince(spinStartDate))
        let drift = (spinFromSpeed - target) / Self.spinResponse * (1 - exp(-Self.spinResponse * elapsed))
        return (spinBaseAngle + 360 * (target * elapsed + drift))
            .truncatingRemainder(dividingBy: 360)
    }

    private func fanBlade(degrees: Double) -> some View {
        Image(systemName: "fan.fill")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundColor(tint.opacity(rpm > 20 ? 0.95 : 0.40))
            .rotationEffect(.degrees(degrees))
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(width: size, height: size)
            .background(
                RadialGradient(
                    colors: [Color.black.opacity(0.10), Color.black.opacity(0.42)],
                    center: .center,
                    startRadius: 4,
                    endRadius: size * 0.58
                )
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

}

private struct MediaSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct MediaShareSheetPresenter: NSViewRepresentable {
    @Binding var payload: MediaSharePayload?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let payload,
              context.coordinator.presentedID != payload.id else {
            return
        }

        context.coordinator.presentedID = payload.id
        context.coordinator.onFinish = {
            NotchUIState.shared.isInteractionHeld = false
        }
        let payloadBinding = $payload
        DispatchQueue.main.async {
            guard nsView.window != nil else {
                payloadBinding.wrappedValue = nil
                NotchUIState.shared.isInteractionHeld = false
                return
            }

            NotchUIState.shared.isInteractionHeld = true
            let picker = NSSharingServicePicker(items: payload.items)
            picker.delegate = context.coordinator
            context.coordinator.picker = picker
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            payloadBinding.wrappedValue = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard context.coordinator.presentedID == payload.id else { return }
                NotchUIState.shared.isInteractionHeld = false
            }
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var presentedID: UUID?
        var picker: NSSharingServicePicker?
        var onFinish: (() -> Void)?

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            onFinish?()
        }
    }
}

private struct BottomRoundedRectangle: Shape {
    var radius: CGFloat
    var tailRadius: CGFloat = 0
    var tailTopInset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let tail = min(tailRadius, rect.width / 2)
        let bodyMinX = rect.minX + tail
        let bodyMaxX = rect.maxX - tail
        let tailTop = rect.minY + tailTopInset
        let radius = min(radius, (bodyMaxX - bodyMinX) / 2, rect.height)

        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        if tail > 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: tailTop))
            path.addArc(
                center: CGPoint(x: rect.maxX, y: tailTop + tail),
                radius: tail,
                startAngle: .degrees(-90),
                endAngle: .degrees(-180),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX - radius, y: rect.maxY),
            control: CGPoint(x: bodyMaxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - radius),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )

        if tail > 0 {
            path.addLine(to: CGPoint(x: bodyMinX, y: tailTop + tail))
            path.addArc(
                center: CGPoint(x: rect.minX, y: tailTop + tail),
                radius: tail,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
        }

        path.addLine(to: rect.origin)
        path.closeSubpath()
        return path
    }
}

private struct LoopingLyricText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 26
    var gap: CGFloat = 34

    @State private var textWidth: CGFloat = 0
    @State private var loopStartDate = Date()

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let shouldLoop = textWidth > availableWidth + 2

            ZStack(alignment: .leading) {
                if shouldLoop {
                    TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                        let distance = max(1, textWidth + gap)
                        let elapsed = max(0, context.date.timeIntervalSince(loopStartDate))
                        let offset = -CGFloat(elapsed.truncatingRemainder(dividingBy: Double(distance / speed))) * speed

                        HStack(spacing: gap) {
                            lyricText
                            lyricText
                        }
                        .offset(x: offset)
                    }
                } else {
                    lyricText
                }

                lyricText
                    .hidden()
                    .background(
                        GeometryReader { textProxy in
                            Color.clear.preference(
                                key: LyricTextWidthPreferenceKey.self,
                                value: textProxy.size.width
                            )
                        }
                    )
            }
            .frame(width: availableWidth, height: proxy.size.height, alignment: .leading)
            .clipped()
            .onPreferenceChange(LyricTextWidthPreferenceKey.self) { width in
                textWidth = width
            }
            .onChange(of: text) { _, _ in
                loopStartDate = Date()
            }
        }
    }

    private var lyricText: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct LyricsSkeletonShimmer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ShimmerSkeletonBar(widthFraction: 0.48, height: 7)
            ShimmerSkeletonBar(widthFraction: 0.82, height: 10)
            ShimmerSkeletonBar(widthFraction: 0.64, height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
    }
}

private struct ShimmerSkeletonBar: View {
    let widthFraction: CGFloat
    let height: CGFloat
    @State private var startDate = Date()

    var body: some View {
        GeometryReader { proxy in
            let barWidth = max(24, proxy.size.width * widthFraction)

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                let progress = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2)
                let shimmerWidth = max(34, barWidth * 0.42)
                let shimmerOffset = -shimmerWidth + (barWidth + shimmerWidth * 2) * progress

                Capsule()
                    .fill(Color.white.opacity(0.075))
                    .frame(width: barWidth, height: height)
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.16),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: shimmerWidth, height: height)
                        .offset(x: shimmerOffset)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .onAppear {
            startDate = Date()
        }
    }
}

private struct LyricTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct GenieCollapseModifier: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: isActive ? 0.22 : 1,
                y: isActive ? 0.08 : 1,
                anchor: .top
            )
            .offset(y: isActive ? -8 : 0)
            .blur(radius: isActive ? 3 : 0)
            .opacity(isActive ? 0 : 1)
    }
}