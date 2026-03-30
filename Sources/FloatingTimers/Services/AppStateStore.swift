import Foundation

struct CGPointSnapshot: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct CGSizeSnapshot: Codable, Equatable {
    var width: Double
    var height: Double

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

struct MemoItemSnapshot: Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var instructionText: String
    var imageData: Data?
    var imageFilename: String?
    var conversationEntries: [MemoConversationEntry]
    var assistantStatus: MemoAssistantStatus
    var lastCapturedImageData: Data?
    var lastFocusedAt: Date?
    var expandedSize: CGSizeSnapshot
    var fontSize: Double?
    var tint: MemoTint

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        instructionText: String,
        imageData: Data?,
        imageFilename: String?,
        conversationEntries: [MemoConversationEntry],
        assistantStatus: MemoAssistantStatus,
        lastCapturedImageData: Data?,
        lastFocusedAt: Date?,
        expandedSize: CGSizeSnapshot,
        fontSize: Double? = nil,
        tint: MemoTint
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.instructionText = instructionText
        self.imageData = imageData
        self.imageFilename = imageFilename
        self.conversationEntries = conversationEntries
        self.assistantStatus = assistantStatus
        self.lastCapturedImageData = lastCapturedImageData
        self.lastFocusedAt = lastFocusedAt
        self.expandedSize = expandedSize
        self.fontSize = fontSize
        self.tint = tint
    }

    init(_ memo: MemoItem) {
        id = memo.id
        createdAt = memo.createdAt
        updatedAt = memo.updatedAt
        instructionText = memo.instructionText
        imageData = memo.imageData
        imageFilename = memo.imageFilename
        conversationEntries = memo.conversationEntries
        assistantStatus = memo.assistantStatus
        lastCapturedImageData = memo.lastCapturedImageData
        lastFocusedAt = memo.lastFocusedAt
        expandedSize = CGSizeSnapshot(memo.expandedSize)
        fontSize = Double(memo.fontSize)
        tint = memo.tint
    }

    func restored(now: Date) -> MemoItem {
        let interruptedEntries = conversationEntries.map { entry -> MemoConversationEntry in
            var updatedEntry = entry
            updatedEntry.isStreaming = false
            return updatedEntry
        }

        let restoredStatus: MemoAssistantStatus
        var restoredConversationEntries = interruptedEntries

        switch assistantStatus {
        case .idle:
            restoredStatus = .idle
        case .capturing, .requesting, .streaming:
            restoredStatus = .idle
            restoredConversationEntries.append(
                MemoConversationEntry(
                    id: UUID(),
                    role: .systemError,
                    createdAt: now,
                    text: "이전 요청이 앱 종료로 중단되었습니다.",
                    imageData: nil,
                    imageFilename: nil,
                    isStreaming: false
                )
            )
        }

        return MemoItem(
            id: id,
            createdAt: createdAt,
            updatedAt: max(updatedAt, now),
            instructionText: instructionText,
            imageData: imageData,
            imageFilename: imageFilename,
            conversationEntries: restoredConversationEntries,
            assistantStatus: restoredStatus,
            lastCapturedImageData: lastCapturedImageData,
            lastFocusedAt: lastFocusedAt,
            expandedSize: expandedSize.cgSize,
            fontSize: MemoItem.clampedFontSize(CGFloat(fontSize ?? Double(MemoItem.defaultFontSize))),
            tint: tint
        )
    }
}

struct FloatingPanelOriginSnapshot: Codable, Equatable {
    var id: UUID
    var origin: CGPointSnapshot
}

struct FloatingPanelOriginsSnapshot: Codable, Equatable {
    var timerOrigins: [FloatingPanelOriginSnapshot]
    var groupOrigins: [FloatingPanelOriginSnapshot]
    var memoOrigins: [FloatingPanelOriginSnapshot]
    var controlPanelOrigin: CGPointSnapshot?
}

struct AIConfigurationStateSnapshot: Codable, Equatable {
    var provider: AIProvider
    var openAIModel: String
    var geminiModel: String
    var selectedOpenAIKeySlot: Int
    var selectedGeminiKeySlot: Int
}

struct AppStateSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var timers: [TimerItem]
    var groups: [TimerGroup]
    var memos: [MemoItemSnapshot]
    var floatingOpacity: Double
    var areFloatingHUDsVisible: Bool
    var controlPanelMode: FloatingPanelMode
    var minimizedTimerIDs: [UUID]
    var minimizedGroupIDs: [UUID]
    var minimizedMemoIDs: [UUID]
    var focusedMemoID: UUID?
    var aiConfiguration: AIConfigurationStateSnapshot
    var panelOrigins: FloatingPanelOriginsSnapshot
}

protocol AppStatePersisting {
    func load() throws -> AppStateSnapshot?
    func save(_ snapshot: AppStateSnapshot) throws
    func clear() throws
}

final class InMemoryAppStateStore: AppStatePersisting {
    private var snapshot: AppStateSnapshot?

    init(snapshot: AppStateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> AppStateSnapshot? {
        snapshot
    }

    func save(_ snapshot: AppStateSnapshot) throws {
        self.snapshot = snapshot
    }

    func clear() throws {
        snapshot = nil
    }
}

final class FileAppStateStore: AppStatePersisting {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager

        let baseURL = applicationSupportURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appendingPathComponent("FloatingTimers", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("state.json", isDirectory: false)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private var backupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("bak.json")
    }

    func load() throws -> AppStateSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return try loadFromBackup()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppStateSnapshot.self, from: data)
        } catch {
            if let recovered = try? loadFromBackup() {
                return recovered
            }
            throw error
        }
    }

    private func loadFromBackup() throws -> AppStateSnapshot? {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: backupURL)
        return try decoder.decode(AppStateSnapshot.self, from: data)
    }

    func save(_ snapshot: AppStateSnapshot) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try? fileManager.replaceItemAt(backupURL, withItemAt: fileURL)
        }
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
    }
}
