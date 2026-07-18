import Foundation
import Combine
import CoreGraphics

enum NotchIslandMetrics {
    static let expandedBodyWidth: CGFloat = 440
    static let collapsedBodySize = CGSize(width: 184, height: 24)
    static let expandedTailRadius: CGFloat = 12
    static let collapsedTailRadius: CGFloat = 6
    static let topOverlap: CGFloat = 10

    static var expandedWidth: CGFloat {
        expandedBodyWidth + expandedTailRadius * 2
    }

    static var collapsedSize: CGSize {
        CGSize(
            width: collapsedBodySize.width + collapsedTailRadius * 2,
            height: collapsedBodySize.height
        )
    }
}

struct NotchPageRequest: Equatable {
    let id = UUID()
    let rawValue: Int
    let direction: Int
    let isRelative: Bool
}

final class NotchUIState: ObservableObject {
    static let shared = NotchUIState()

    @Published var isExpanded: Bool = false
    @Published var isPinned: Bool = true
    @Published var expandedHeight: CGFloat = 148
    @Published var isInteractionHeld: Bool = false
    @Published var pageRequest: NotchPageRequest?

    private init() {}

    func requestPage(rawValue: Int, direction: Int = 1) {
        pageRequest = NotchPageRequest(rawValue: rawValue, direction: direction, isRelative: false)
    }

    func requestRelativePage(direction: Int) {
        pageRequest = NotchPageRequest(rawValue: direction, direction: direction, isRelative: true)
    }
}
