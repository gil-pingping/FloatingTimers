import XCTest
@testable import FloatingTimers

final class AppStateStoreTests: XCTestCase {
    
    func testMemoItemSnapshotRestoresInterruptedStateToIdleWithError() {
        let now = Date()
        let past = now.addingTimeInterval(-10)
        
        let streamingEntry = MemoConversationEntry(
            id: UUID(),
            role: .assistant,
            createdAt: past,
            text: "partial response...",
            imageData: nil,
            imageFilename: nil,
            isStreaming: true
        )
        
        let snapshot = MemoItemSnapshot(
            id: UUID(),
            createdAt: past,
            updatedAt: past,
            instructionText: "test memo",
            imageData: nil,
            imageFilename: nil,
            conversationEntries: [streamingEntry],
            assistantStatus: .streaming,
            lastCapturedImageData: nil,
            lastFocusedAt: nil,
            expandedSize: CGSizeSnapshot(CGSize(width: 200, height: 200)),
            fontSize: 15,
            tint: .default
        )
        
        let restored = snapshot.restored(now: now)
        
        XCTAssertEqual(restored.assistantStatus, .idle)
        XCTAssertEqual(restored.conversationEntries.count, 2)
        XCTAssertFalse(restored.conversationEntries[0].isStreaming) // Should be set to false
        
        let errorEntry = restored.conversationEntries.last!
        XCTAssertEqual(errorEntry.role, .systemError)
        XCTAssertEqual(errorEntry.text, "이전 요청이 앱 종료로 중단되었습니다.")
        XCTAssertFalse(errorEntry.isStreaming)
    }
    
    func testMemoItemSnapshotRestoresIdleStateWithoutError() {
        let now = Date()
        let past = now.addingTimeInterval(-10)
        
        let snapshot = MemoItemSnapshot(
            id: UUID(),
            createdAt: past,
            updatedAt: past,
            instructionText: "idle memo",
            imageData: nil,
            imageFilename: nil,
            conversationEntries: [],
            assistantStatus: .idle,
            lastCapturedImageData: nil,
            lastFocusedAt: nil,
            expandedSize: CGSizeSnapshot(CGSize(width: 200, height: 200)),
            fontSize: 14,
            tint: .default
        )
        
        let restored = snapshot.restored(now: now)
        
        XCTAssertEqual(restored.assistantStatus, .idle)
        XCTAssertTrue(restored.conversationEntries.isEmpty)
    }
}
