import Foundation

enum FloatingPanelMode: String, CaseIterable, Codable {
    case expanded
    case minimized
    case hidden

    var isVisible: Bool {
        self != .hidden
    }

    var label: String {
        switch self {
        case .expanded:
            return "펼쳐짐"
        case .minimized:
            return "접힘"
        case .hidden:
            return "숨김"
        }
    }
}
