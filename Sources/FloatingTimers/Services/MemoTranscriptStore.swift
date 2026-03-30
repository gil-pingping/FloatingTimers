import Foundation

protocol MemoTranscriptPersisting: Sendable {
    func appendAssistantResponse(memo: MemoItem, responseText: String, at date: Date) async throws
}

final class InMemoryMemoTranscriptStore: MemoTranscriptPersisting {
    func appendAssistantResponse(memo _: MemoItem, responseText _: String, at _: Date) async throws {}
}

actor FileMemoTranscriptStore: MemoTranscriptPersisting {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let formatter: ISO8601DateFormatter

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager

        let baseURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = baseURL
            .appendingPathComponent("FloatingTimers", isDirectory: true)
            .appendingPathComponent("memo_answers", isDirectory: true)

        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func appendAssistantResponse(memo: MemoItem, responseText: String, at date: Date) async throws {
        let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("\(memo.id.uuidString).txt", isDirectory: false)
        let header = "# \(memo.displayTitle)\n"
        let timestamp = formatter.string(from: date)
        let block = """

        [\(timestamp)]
        \(trimmedResponse)
        """

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = block.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            let initial = header + block
            try initial.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
