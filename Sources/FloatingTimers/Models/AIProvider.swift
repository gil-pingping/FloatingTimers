import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "openai"
    case gemini = "gemini"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-4.1"
        case .gemini:
            return "gemini-2.5-flash"
        }
    }

    var envKey: String {
        switch self {
        case .openAI:
            return "OPENAI_API_KEY"
        case .gemini:
            return "GEMINI_API_KEY"
        }
    }
}
