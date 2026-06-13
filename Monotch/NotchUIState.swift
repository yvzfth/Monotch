import Foundation
import Combine
import CoreGraphics

final class NotchUIState: ObservableObject {
    static let shared = NotchUIState()

    @Published var isExpanded: Bool = false
    @Published var isPinned: Bool = true
    @Published var expandedHeight: CGFloat = 148
    @Published var isInteractionHeld: Bool = false

    private init() {}
}
