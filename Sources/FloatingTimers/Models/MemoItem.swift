import AppKit
import CoreGraphics
import Foundation

struct MemoTint: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let `default` = MemoTint(red: 0.46, green: 0.36, blue: 0.24, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let rgbColor = nsColor.usingColorSpace(.deviceRGB) ?? nsColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        self.init(
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent),
            alpha: Double(rgbColor.alphaComponent)
        )
    }
}

struct MemoItem: Identifiable, Equatable {
    static let defaultExpandedWidth: CGFloat = 232
    static let defaultExpandedHeight: CGFloat = 252
    static let defaultExpandedHeightWithImage: CGFloat = 252
    static let minimumExpandedWidth: CGFloat = 140
    static let maximumExpandedWidth: CGFloat = 520
    static let minimumExpandedHeight: CGFloat = 120
    static let minimumExpandedHeightWithImage: CGFloat = 120
    static let maximumExpandedHeight: CGFloat = 640
    static let defaultFontSize: CGFloat = 12
    static let minimumFontSize: CGFloat = 9
    static let maximumFontSize: CGFloat = 20

    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var instructionText: String
    var imageData: Data?
    var imageFilename: String?
    var conversationEntries: [MemoConversationEntry]
    var assistantStatus: MemoAssistantStatus
    var lastCapturedImageData: Data?
    var lastFocusedAt: Date?
    var expandedSize: CGSize
    var fontSize: CGFloat
    var tint: MemoTint

    var hasImage: Bool {
        imageData != nil
    }

    var hasConversation: Bool {
        !conversationEntries.isEmpty
    }

    var latestConversationText: String? {
        conversationEntries
            .last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .text
    }

    static func defaultExpandedSize(hasImage: Bool) -> CGSize {
        CGSize(
            width: defaultExpandedWidth,
            height: hasImage ? defaultExpandedHeightWithImage : defaultExpandedHeight
        )
    }

    static func minimumExpandedSize(hasImage: Bool) -> CGSize {
        CGSize(
            width: minimumExpandedWidth,
            height: hasImage ? minimumExpandedHeightWithImage : minimumExpandedHeight
        )
    }

    static func clampedExpandedSize(_ size: CGSize, hasImage: Bool) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumExpandedWidth), maximumExpandedWidth),
            height: min(max(size.height, hasImage ? minimumExpandedHeightWithImage : minimumExpandedHeight), maximumExpandedHeight)
        )
    }

    static func clampedFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minimumFontSize), maximumFontSize)
    }

    var displayTitle: String {
        let trimmedInstruction = instructionText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        if let trimmedInstruction {
            return String(trimmedInstruction.prefix(24))
        }

        if let latestConversationText {
            return String(latestConversationText.prefix(24))
        }

        if hasImage {
            return imageFilename ?? "이미지 메모"
        }

        return "AI 메모"
    }

    var previewLine: String {
        if let latestConversationText {
            return String(latestConversationText.prefix(88))
        }

        let compactInstruction = instructionText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        if let compactInstruction {
            return String(compactInstruction.prefix(64))
        }

        if hasImage {
            return "캡처와 함께 질문할 수 있는 AI 메모"
        }

        return "단축키로 화면을 캡처해 질문하고 답변을 같은 카드에 누적합니다."
    }

    var activePromptText: String {
        let trimmedInstruction = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstruction.isEmpty {
            return trimmedInstruction
        }

        return "이 화면에서 중요한 내용, 문제점, 다음 액션을 한국어로 간단히 정리해줘."
    }

    var latestAssistantEntry: MemoConversationEntry? {
        conversationEntries.last(where: { $0.role == .assistant })
    }

    var latestUserEntry: MemoConversationEntry? {
        conversationEntries.last(where: { $0.role == .userPrompt || $0.role == .userCapture })
    }

    var latestErrorEntry: MemoConversationEntry? {
        conversationEntries.last(where: { $0.role == .systemError })
    }

    var latestResponseEntry: MemoConversationEntry? {
        conversationEntries.last(where: { $0.role == .assistant || $0.role == .systemError })
    }

    var askTranscriptText: String {
        let values = conversationEntries
            .filter { $0.role == .userPrompt || $0.role == .userCapture }
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.joined(separator: "\n\n")
    }

    var answerTranscriptText: String {
        let values = conversationEntries
            .filter { $0.role == .assistant || $0.role == .systemError }
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return values.joined(separator: "\n\n")
    }

    var statusSummary: String {
        switch assistantStatus {
        case .idle:
            return hasConversation ? "대화 누적" : "준비됨"
        case .capturing:
            return "화면 캡처 중"
        case .requesting:
            return "요청 전송 중"
        case .streaming:
            return "응답 스트리밍 중"
        }
    }

    func debugExport(
        providerLabel: String,
        model: String,
        hotkey: String,
        errorOnly: Bool = false
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let relevantEntries = errorOnly
            ? conversationEntries.filter { $0.role == .systemError }
            : conversationEntries

        let transcript = relevantEntries.isEmpty
            ? "(none)"
            : relevantEntries.map { entry in
                var lines: [String] = []
                lines.append("[\(entry.role.label) @ \(formatter.string(from: entry.createdAt))]")

                if entry.hasImage {
                    let attachmentName = entry.imageFilename?.isEmpty == false ? entry.imageFilename! : "embedded image"
                    lines.append("attachment: \(attachmentName)")
                }

                let body = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(body.isEmpty ? "(empty)" : body)
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")

        let prompt = activePromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastError = latestErrorEntry?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(none)"
        let referenceImageSummary = hasImage ? (imageFilename ?? "attached") : "none"
        let captureImageSummary = lastCapturedImageData == nil ? "none" : "attached"

        return """
        FloatingTimers AI Debug
        exported_at: \(formatter.string(from: Date()))
        provider: \(providerLabel)
        model: \(model.isEmpty ? "(empty)" : model)
        status: \(assistantStatus.rawValue)
        memo_title: \(displayTitle)
        hotkey: \(hotkey)
        reference_image: \(referenceImageSummary)
        last_capture_image: \(captureImageSummary)
        last_error: \(lastError)

        prompt:
        \(prompt.isEmpty ? "(empty)" : prompt)

        transcript:
        \(transcript)
        """
    }
}
