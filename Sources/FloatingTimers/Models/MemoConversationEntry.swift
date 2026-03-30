import Foundation

enum MemoConversationRole: String, Codable, Equatable {
    case userPrompt
    case userCapture
    case assistant
    case systemError

    var label: String {
        switch self {
        case .userPrompt:
            return "USER"
        case .userCapture:
            return "CAPTURE"
        case .assistant:
            return "ASSISTANT"
        case .systemError:
            return "ERROR"
        }
    }
}

enum MemoAssistantStatus: String, Codable, Equatable {
    case idle
    case capturing
    case requesting
    case streaming

    var label: String {
        switch self {
        case .idle:
            return "ready"
        case .capturing:
            return "capturing"
        case .requesting:
            return "requesting"
        case .streaming:
            return "streaming"
        }
    }
}

struct MemoConversationEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MemoConversationRole
    let createdAt: Date
    var text: String
    var imageData: Data?
    var imageFilename: String?
    var isStreaming: Bool

    var hasImage: Bool {
        imageData != nil
    }
}
