import Foundation
import Combine
import AppKit

struct ClipboardTextItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let attributedText: AttributedString?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        attributedText: AttributedString? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.attributedText = attributedText
        self.createdAt = createdAt
    }

    var preview: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func == (lhs: ClipboardTextItem, rhs: ClipboardTextItem) -> Bool {
        lhs.text == rhs.text
    }
}

struct ClipboardImageItem: Identifiable, Equatable {
    let id: UUID
    let data: Data
    let typeIdentifier: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        data: Data,
        typeIdentifier: String = NSPasteboard.PasteboardType.png.rawValue,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.data = data
        self.typeIdentifier = typeIdentifier
        self.createdAt = createdAt
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(typeIdentifier)
    }

    var image: NSImage? {
        NSImage(data: data)
    }

    static func == (lhs: ClipboardImageItem, rhs: ClipboardImageItem) -> Bool {
        lhs.data == rhs.data
    }
}

final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var recentFileItems: [ShelfItem] = [] {
        didSet { saveHistoryIfNeeded() }
    }
    @Published var recentTextItems: [ClipboardTextItem] = [] {
        didSet { saveHistoryIfNeeded() }
    }
    @Published var recentImageItems: [ClipboardImageItem] = [] {
        didSet { saveHistoryIfNeeded() }
    }
    @Published var folderShelfURL: URL = ClipboardManager.defaultFolderShelfURL {
        didSet {
            saveHistoryIfNeeded()
            if isFolderShelfMonitoringActive {
                refreshFolderShelf()
            } else {
                folderShelfItems = []
            }
        }
    }
    @Published private(set) var folderShelfItems: [ShelfItem] = []

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var isRestoringHistory = false
    private var lastFolderShelfRefresh = Date.distantPast
    private var isFolderShelfMonitoringActive = false

    private init() {
        loadHistory()
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.2
    }

    private func tick() {
        checkPasteboard()
        if isFolderShelfMonitoringActive {
            refreshFolderShelfIfNeeded()
        }
    }

    func setFolderShelfMonitoringActive(_ active: Bool) {
        guard isFolderShelfMonitoringActive != active else { return }
        isFolderShelfMonitoringActive = active

        if active {
            refreshFolderShelf()
        }
    }

    var folderShelfTitle: String {
        folderShelfURL.lastPathComponent.isEmpty ? "Downloads" : folderShelfURL.lastPathComponent
    }

    var isFolderShelfCustom: Bool {
        folderShelfURL.standardizedFileURL != ClipboardManager.defaultFolderShelfURL.standardizedFileURL
    }

    func resetFolderShelfLocation() {
        folderShelfURL = ClipboardManager.defaultFolderShelfURL
    }

    func chooseFolderShelfLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderShelfURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderShelfURL = url.standardizedFileURL
    }

    func refreshFolderShelf() {
        let folderURL = folderShelfURL.standardizedFileURL
        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .creationDateKey,
            .isHiddenKey
        ]

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let visibleURLs = urls.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isHidden != true
        }

        let sortedURLs = visibleURLs.sorted { lhs, rhs in
            folderSortDate(for: lhs) > folderSortDate(for: rhs)
        }

        let existingItemsByURL = Dictionary(
            uniqueKeysWithValues: folderShelfItems.map { ($0.url.standardizedFileURL, $0) }
        )
        let refreshedItems = Array(sortedURLs.prefix(20)).map { url in
            existingItemsByURL[url.standardizedFileURL] ?? ShelfItem(url: url)
        }

        if refreshedItems.map(\.url.standardizedFileURL) != folderShelfItems.map(\.url.standardizedFileURL) {
            folderShelfItems = refreshedItems
        }
        lastFolderShelfRefresh = Date()
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            let fileURLs = urls.filter(\.isFileURL)
            guard fileURLs.isEmpty else {
                let newItems = fileURLs.map { ShelfItem(url: $0) }
                DispatchQueue.main.async {
                    self.recentFileItems = Array((newItems + self.recentFileItems).uniquedByURL().prefix(20))
                }
                return
            }
        }

        if let imageItem = imageItem(from: pasteboard) {
            DispatchQueue.main.async {
                self.recentImageItems = Array(([imageItem] + self.recentImageItems.filter { $0.data != imageItem.data }).prefix(16))
            }
            return
        }

        guard let string = pasteboard.string(forType: .string) else { return }

        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return }
        let richText = attributedString(from: pasteboard)

        DispatchQueue.main.async {
            let newItem = ClipboardTextItem(text: string, attributedText: richText)
            self.recentTextItems = Array(([newItem] + self.recentTextItems.filter { $0.text != string }).prefix(16))
        }
    }

    @discardableResult
    func copyLatestTextToPasteboard() -> Bool {
        guard let item = recentTextItems.first else { return false }
        copyTextToPasteboard(item)
        return true
    }

    @discardableResult
    func copyLatestImageToPasteboard() -> Bool {
        guard let item = recentImageItems.first else { return false }
        copyImageToPasteboard(item)
        return true
    }

    @discardableResult
    func copyLatestFileToPasteboard() -> Bool {
        guard let item = recentFileItems.first else { return false }
        copyFileToPasteboard(item)
        return true
    }

    func clearHistory() {
        recentTextItems = []
        recentImageItems = []
        recentFileItems = []
    }

    func copyTextToPasteboard(_ item: ClipboardTextItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        if let attributedText = item.attributedText {
            let nsAttributedText = NSAttributedString(attributedText)
            if let rtf = nsAttributedText.rtf(from: NSRange(location: 0, length: nsAttributedText.length)) {
                pasteboard.setData(rtf, forType: .rtf)
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    func copyImageToPasteboard(_ item: ClipboardImageItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(item.data, forType: item.pasteboardType)

        if item.pasteboardType != .png {
            pasteboard.setData(item.data, forType: .png)
        }

        if let tiffData = item.image?.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }

        lastChangeCount = pasteboard.changeCount
    }

    func copyFileToPasteboard(_ item: ShelfItem) {
        item.withSecurityScopedAccess {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([item.url as NSURL])
            lastChangeCount = pasteboard.changeCount
        }
    }
}

private extension ClipboardManager {
    static var defaultFolderShelfURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    struct StoredHistory: Codable {
        var textItems: [StoredTextItem]
        var imageItems: [StoredImageItem]?
        var fileItems: [StoredFileItem]
        var folderShelfPath: String?
        var folderShelfBookmarkData: Data?
    }

    struct StoredTextItem: Codable {
        var id: UUID
        var text: String
        var rtfData: Data?
        var createdAt: Date?
    }

    struct StoredImageItem: Codable {
        var id: UUID
        var data: Data
        var typeIdentifier: String
        var createdAt: Date?
    }

    struct StoredFileItem: Codable {
        var id: UUID
        var path: String
        var bookmarkData: Data?
    }

    var historyURL: URL {
        applicationSupportDirectory.appendingPathComponent("clipboard-history.json")
    }

    var applicationSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent("Monotch", isDirectory: true)
    }

    func loadHistory() {
        isRestoringHistory = true
        var shouldRewriteHistory = false
        defer {
            isRestoringHistory = false
            if shouldRewriteHistory {
                saveHistoryIfNeeded()
            }
        }

        guard let data = try? Data(contentsOf: historyURL),
              let history = try? JSONDecoder().decode(StoredHistory.self, from: data) else {
            return
        }

        recentTextItems = history.textItems.map { item in
            ClipboardTextItem(
                id: item.id,
                text: item.text,
                attributedText: attributedString(fromRTFData: item.rtfData),
                createdAt: item.createdAt ?? Date.distantPast
            )
        }

        recentImageItems = (history.imageItems ?? []).compactMap { item in
            guard
                let image = NSImage(data: item.data),
                let data = pngData(from: image, maxPixelSize: 900)
            else {
                return nil
            }
            if data.count != item.data.count {
                shouldRewriteHistory = true
            }

            return ClipboardImageItem(
                id: item.id,
                data: data,
                typeIdentifier: item.typeIdentifier,
                createdAt: item.createdAt ?? Date.distantPast
            )
        }

        recentFileItems = history.fileItems.compactMap { item in
            guard let bookmarkData = item.bookmarkData,
                  let url = ShelfItem.resolveBookmarkedURL(bookmarkData) else {
                return nil
            }

            let exists = url.startAccessingSecurityScopedResource()
            defer {
                if exists {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: item.id, url: url, bookmarkData: bookmarkData)
        }

        if let bookmarkData = history.folderShelfBookmarkData,
           let url = ShelfItem.resolveBookmarkedURL(bookmarkData) {
            folderShelfURL = url.standardizedFileURL
        } else if let path = history.folderShelfPath,
                  FileManager.default.fileExists(atPath: path) {
            folderShelfURL = URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    func saveHistoryIfNeeded() {
        guard isRestoringHistory == false else { return }

        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            let history = StoredHistory(
                textItems: recentTextItems.map { item in
                    StoredTextItem(
                        id: item.id,
                        text: item.text,
                        rtfData: rtfData(from: item.attributedText),
                        createdAt: item.createdAt
                    )
                },
                imageItems: recentImageItems.map { item in
                    StoredImageItem(
                        id: item.id,
                        data: item.data,
                        typeIdentifier: item.typeIdentifier,
                        createdAt: item.createdAt
                    )
                },
                fileItems: recentFileItems.map { item in
                    StoredFileItem(id: item.id, path: item.url.path, bookmarkData: item.bookmarkData)
                },
                folderShelfPath: folderShelfURL.path,
                folderShelfBookmarkData: folderBookmarkData(for: folderShelfURL)
            )

            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            NSLog("Monotch clipboard history save failed: \(error.localizedDescription)")
        }
    }

    func refreshFolderShelfIfNeeded() {
        guard Date().timeIntervalSince(lastFolderShelfRefresh) >= 5 else { return }
        refreshFolderShelf()
    }

    func folderSortDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
    }

    func folderBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func imageItem(from pasteboard: NSPasteboard) -> ClipboardImageItem? {
        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ]

        for type in preferredTypes {
            guard let data = pasteboard.data(forType: type),
                  let image = NSImage(data: data),
                  let pngData = pngData(from: image, maxPixelSize: 900) else {
                continue
            }

            return ClipboardImageItem(data: pngData)
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let data = pngData(from: image, maxPixelSize: 900) else {
            return nil
        }

        return ClipboardImageItem(data: data)
    }

    func pngData(from image: NSImage, maxPixelSize: CGFloat? = nil) -> Data? {
        let outputImage: NSImage
        if let maxPixelSize {
            outputImage = resizedImage(image, maxPixelSize: maxPixelSize)
        } else {
            outputImage = image
        }

        guard let tiffData = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    func resizedImage(_ image: NSImage, maxPixelSize: CGFloat) -> NSImage {
        let sourceSize = image.size
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxPixelSize, longestSide > 0 else { return image }

        let scale = maxPixelSize / longestSide
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()
        return resized
    }

    func attributedString(from pasteboard: NSPasteboard) -> AttributedString? {
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = nsAttributedString(from: rtf, documentType: .rtf) {
            return AttributedString(normalizedRichText(attributed))
        }

        if let html = pasteboard.data(forType: .html),
           let attributed = nsAttributedString(from: html, documentType: .html) {
            return AttributedString(normalizedRichText(attributed))
        }

        return nil
    }

    func attributedString(fromRTFData data: Data?) -> AttributedString? {
        guard let data,
              let attributed = nsAttributedString(from: data, documentType: .rtf) else {
            return nil
        }

        return AttributedString(normalizedRichText(attributed))
    }

    func rtfData(from attributedText: AttributedString?) -> Data? {
        guard let attributedText else { return nil }

        let nsAttributedText = NSAttributedString(attributedText)
        return nsAttributedText.rtf(from: NSRange(location: 0, length: nsAttributedText.length))
    }

    func nsAttributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    func normalizedRichText(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source.string)
        let fullRange = NSRange(location: 0, length: source.length)

        source.enumerateAttributes(in: fullRange) { attributes, range, _ in
            var normalized: [NSAttributedString.Key: Any] = [
                .font: modernFont(from: attributes[.font] as? NSFont),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88)
            ]

            if let underline = attributes[.underlineStyle] {
                normalized[.underlineStyle] = underline
            }

            if let strike = attributes[.strikethroughStyle] {
                normalized[.strikethroughStyle] = strike
            }

            if let paragraph = attributes[.paragraphStyle] {
                normalized[.paragraphStyle] = paragraph
            }

            result.addAttributes(normalized, range: range)
        }

        return result
    }

    func modernFont(from sourceFont: NSFont?) -> NSFont {
        let size: CGFloat = 12
        let traits = sourceFont?.fontDescriptor.symbolicTraits ?? []
        let isBold = traits.contains(.bold)
        let isItalic = traits.contains(.italic)
        let weight: NSFont.Weight = isBold ? .semibold : .regular
        let baseFont = NSFont.systemFont(ofSize: size, weight: weight)

        guard isItalic else { return baseFont }
        return NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }
}

private extension Array where Element == ShelfItem {
    func uniquedByURL() -> [ShelfItem] {
        var seen = Set<URL>()
        return filter { item in
            let key = item.url.standardizedFileURL
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }
}
