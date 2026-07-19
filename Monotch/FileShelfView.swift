import QuickLookThumbnailing
import SwiftUI
import AppKit
struct FileShelfView: View {
    var title = "Files"
    @Binding var items: [ShelfItem]
    var onRemove: (() -> Void)?
    @State private var isTargeted = false
    @State private var copiedItemID: UUID?
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
                Spacer()
                if !items.isEmpty {
                    if isConfirmingClear {
                        inlineConfirmPill(
                            message: String(localized: "Clear items?", comment: "Inline confirmation to clear all items from a tray."),
                            onConfirm: {
                                withAnimation(.easeOut(duration: 0.16)) { isConfirmingClear = false }
                                items.removeAll()
                            },
                            onCancel: {
                                withAnimation(.easeOut(duration: 0.16)) { isConfirmingClear = false }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { isConfirmingClear = true }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.72))
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Clear items", comment: "Tooltip for the button that clears all items from the files tray."))
                    }
                }

                if let onRemove {
                    ShelfRemoveButton(action: onRemove)
                }
            }
            .frame(height: 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if items.isEmpty {
                        emptyDropTarget
                    } else {
                        ForEach(items) { item in
                            fileItemView(item)
                            .onDrag {
                                item.withSecurityScopedAccess {
                                    NSItemProvider(object: item.url as NSURL)
                                }
                            }
                            .contextMenu {
                                Button("Show in Finder") {
                                    item.withSecurityScopedAccess {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    }
                                }
                                Button("Remove") {
                                    if let idx = items.firstIndex(of: item) {
                                        items.remove(at: idx)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 72)
            .background(dropBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            FileDropReceiver(isTargeted: $isTargeted) { urls in
                addDroppedFiles(urls)
            }
        )
    }

    private var emptyDropTarget: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 13, weight: .semibold))

            Text("Drop files here")
                .font(.caption2)
        }
        .foregroundColor(.white.opacity(0.46))
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 8)
    }

    private var dropBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isTargeted ? Color.white.opacity(0.12) : Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isTargeted ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.16), value: isTargeted)
    }

    private func fileItemView(_ item: ShelfItem) -> some View {
        let isCopied = copiedItemID == item.id

        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 3) {
                FilePreviewThumbnail(item: item)
                    .frame(width: 38, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(item.shortDisplayName)
                    .lineLimit(1)
                    .font(.caption2)
                    .frame(width: 58)
            }
            .foregroundColor(.white.opacity(0.86))
            .padding(.vertical, 5)
            .padding(.horizontal, 5)

            if isCopied {
                copyBlinkIcon
                    .padding(4)
                    .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .background(fileItemBackground(isCopied: isCopied))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(fileItemStroke(isCopied: isCopied), lineWidth: 1)
        )
        .shadow(color: .white.opacity(isCopied ? 0.10 : 0), radius: 8)
        .animation(.easeOut(duration: 0.18), value: isCopied)
        .help(item.displayName)
        .onTapGesture(count: 2) {
            item.withSecurityScopedAccess {
                _ = NSWorkspace.shared.open(item.url)
            }
        }
        .onTapGesture(count: 1) {
            ClipboardManager.shared.copyFileToPasteboard(item)
            showCopied(item.id)
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

    private func fileItemBackground(isCopied: Bool) -> Color {
        isCopied ? Color.white.opacity(0.13) : Color.white.opacity(0.07)
    }

    private func fileItemStroke(isCopied: Bool) -> Color {
        isCopied ? Color.white.opacity(0.28) : Color.white.opacity(0.06)
    }

    private func showCopied(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            copiedItemID = id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard copiedItemID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedItemID = nil
            }
        }
    }

    private func addDroppedFiles(_ urls: [URL]) {
        DispatchQueue.main.async {
            for url in urls where url.isFileURL {
                let normalizedURL = url.standardizedFileURL
                if let existingIndex = items.firstIndex(where: { $0.url.standardizedFileURL == normalizedURL }) {
                    items.remove(at: existingIndex)
                }
                items.insert(ShelfItem(url: normalizedURL), at: 0)
            }
        }
    }
}

struct ShelfRemoveButton: View {
    var action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        if isConfirming {
            inlineConfirmPill(
                message: String(localized: "Remove tray?", comment: "Inline confirmation to remove a clipboard tray."),
                onConfirm: {
                    withAnimation(.easeOut(duration: 0.16)) { isConfirming = false }
                    action()
                },
                onCancel: {
                    withAnimation(.easeOut(duration: 0.16)) { isConfirming = false }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { isConfirming = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.40))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Remove this tray", comment: "Tooltip for the button that hides a clipboard tray."))
        }
    }
}

func inlineConfirmPill(
    message: String,
    onConfirm: @escaping () -> Void,
    onCancel: @escaping () -> Void
) -> some View {
    HStack(spacing: 4) {
        Text(message)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.80))
            .lineLimit(1)

        Button(action: onConfirm) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.black.opacity(0.85))
                .frame(width: 16, height: 16)
                .background(Color.red.opacity(0.90))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)

        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.70))
                .frame(width: 16, height: 16)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(Color.white.opacity(0.08)))
    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
}

struct FolderShelfView: View {
    var title: String
    var items: [ShelfItem]
    var onChooseFolder: () -> Void
    var onRefresh: () -> Void
    var onRemove: (() -> Void)?
    @State private var copiedItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                }
                .buttonStyle(.borderless)
                .help("Refresh folder")

                Button(action: onChooseFolder) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.72))
                }
                .buttonStyle(.borderless)
                .help("Choose folder")

                if let onRemove {
                    ShelfRemoveButton(action: onRemove)
                }
            }
            .frame(height: 22)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if items.isEmpty {
                        emptyFolderView
                    } else {
                        ForEach(items) { item in
                            folderItemView(item)
                                .onDrag {
                                    item.withSecurityScopedAccess {
                                        NSItemProvider(object: item.url as NSURL)
                                    }
                                }
                                .contextMenu {
                                    Button("Show in Finder") {
                                        item.withSecurityScopedAccess {
                                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                        }
                                    }
                                    Button("Copy") {
                                        ClipboardManager.shared.copyFileToPasteboard(item)
                                        showCopied(item.id)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 72)
            .background(folderBackground)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyFolderView: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .semibold))

            Text("No files in folder")
                .font(.caption2)
        }
        .foregroundColor(.white.opacity(0.46))
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 8)
    }

    private var folderBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func folderItemView(_ item: ShelfItem) -> some View {
        let isCopied = copiedItemID == item.id

        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 3) {
                FilePreviewThumbnail(item: item)
                    .frame(width: 38, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(item.shortDisplayName)
                    .lineLimit(1)
                    .font(.caption2)
                    .frame(width: 58)
            }
            .foregroundColor(.white.opacity(0.86))
            .padding(.vertical, 5)
            .padding(.horizontal, 5)

            if isCopied {
                copyBlinkIcon
                    .padding(4)
                    .transition(.scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .background(isCopied ? Color.white.opacity(0.13) : Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isCopied ? Color.white.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .white.opacity(isCopied ? 0.10 : 0), radius: 8)
        .animation(.easeOut(duration: 0.18), value: isCopied)
        .help(item.displayName)
        .onTapGesture(count: 2) {
            item.withSecurityScopedAccess {
                _ = NSWorkspace.shared.open(item.url)
            }
        }
        .onTapGesture(count: 1) {
            ClipboardManager.shared.copyFileToPasteboard(item)
            showCopied(item.id)
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

    private func showCopied(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            copiedItemID = id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard copiedItemID == id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedItemID = nil
            }
        }
    }
}

private struct FileDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onTargetChanged = { isTargeted = $0 }
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onTargetChanged = { isTargeted = $0 }
        nsView.onDrop = onDrop
    }

    final class DropView: NSView {
        var onTargetChanged: ((Bool) -> Void)?
        var onDrop: (([URL]) -> Void)?
        private let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            registerForFileDrops()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            registerForFileDrops()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                return bounds.contains(point) ? self : nil
            default:
                return nil
            }
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard fileURLs(from: sender.draggingPasteboard).isEmpty == false else {
                return []
            }
            onTargetChanged?(true)
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onTargetChanged?(false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = fileURLs(from: sender.draggingPasteboard)
            onTargetChanged?(false)
            guard urls.isEmpty == false else { return false }
            onDrop?(urls)
            return true
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            onTargetChanged?(false)
        }

        private func registerForFileDrops() {
            registerForDraggedTypes([
                .fileURL,
                .URL,
                .string,
                filenamesPasteboardType
            ])
        }

        private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
            var urls: [URL] = []

            if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], urls.isEmpty == false {
                return urls.filter(\.isFileURL)
            }

            if let filenames = pasteboard.propertyList(
                forType: filenamesPasteboardType
            ) as? [String] {
                urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
            }

            for item in pasteboard.pasteboardItems ?? [] {
                for type in item.types {
                    if type == .fileURL, let data = item.data(forType: type) {
                        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                            urls.append(url)
                        }
                    }

                    if type == .URL || type == .string || type.rawValue == "public.url",
                       let string = item.string(forType: type),
                       let url = fileURL(from: string) {
                        urls.append(url)
                    }

                    if type == filenamesPasteboardType,
                       let filenames = item.propertyList(forType: type) as? [String] {
                        urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
                    }
                }
            }

            var seen = Set<URL>()
            return urls.filter { url in
                let key = url.standardizedFileURL
                guard url.isFileURL, seen.contains(key) == false else { return false }
                seen.insert(key)
                return true
            }
        }

        private func fileURL(from string: String) -> URL? {
            if let url = URL(string: string), url.isFileURL {
                return url
            }

            let expandedPath = (string as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return URL(fileURLWithPath: expandedPath)
            }

            return nil
        }
    }
}

private struct FilePreviewThumbnail: View {
    let item: ShelfItem
    @State private var thumbnail: NSImage?
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.28))

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                item.icon
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            }
        }
        .clipped()
        .task(id: item.url) {
            if let cachedThumbnail = Self.cache.object(forKey: item.url.standardizedFileURL as NSURL) {
                thumbnail = cachedThumbnail
                return
            }

            thumbnail = await makeThumbnail(for: item.url)
        }
    }

    private func makeThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 76, height: 60),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            let didStartAccessing = item.url.startAccessingSecurityScopedResource()
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                if didStartAccessing {
                    item.url.stopAccessingSecurityScopedResource()
                }
                if let image = representation?.nsImage {
                    Self.cache.setObject(image, forKey: url.standardizedFileURL as NSURL, cost: 256 * 256 * 4)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
