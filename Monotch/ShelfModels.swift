import Foundation
import SwiftUI
import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let bookmarkData: Data?

    init(id: UUID = UUID(), url: URL, bookmarkData: Data? = nil) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData ?? Self.makeBookmarkData(for: url)
    }

    var displayName: String {
        url.lastPathComponent
    }

    var shortDisplayName: String {
        let name = displayName
        guard name.count > 10 else { return name }
        return "\(name.prefix(10))..."
    }

    var icon: Image {
        let nsImage: NSImage = withSecurityScopedAccess {
            NSWorkspace.shared.icon(forFile: url.path)
        }
        return Image(nsImage: nsImage)
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.url.standardizedFileURL == rhs.url.standardizedFileURL
    }

    func withSecurityScopedAccess<T>(_ work: () -> T) -> T {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return work()
    }

    private static func makeBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmarkedURL(_ bookmarkData: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
