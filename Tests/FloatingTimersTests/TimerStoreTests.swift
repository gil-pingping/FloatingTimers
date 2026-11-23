import XCTest
@testable import FloatingTimers

@MainActor
final class TimerStoreTests: XCTestCase {
    func testSingleTimerLifecycle() throws {
        let alerts = MockAlertManager()
        var currentDate = Date(timeIntervalSince1970: 0)
        let store = TimerStore(
            alertManager: alerts,
            nowProvider: { currentDate },
            autoStartTicker: false
        )

        let timerID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 1, seconds: 20))

        store.start(timerID)
        XCTAssertEqual(store.timer(for: timerID)?.state, .running)

        currentDate = currentDate.addingTimeInterval(25)
        store.pause(timerID)

        let pausedTimer = try XCTUnwrap(store.timer(for: timerID))
        XCTAssertEqual(pausedTimer.state, .paused)
        XCTAssertEqual(pausedTimer.remainingWholeSeconds, 55)

        store.reset(timerID)
        XCTAssertEqual(store.timer(for: timerID)?.state, .idle)
        XCTAssertEqual(store.timer(for: timerID)?.remainingWholeSeconds, 80)
    }

    func testFinishedTimerNotifiesOnlyOnce() throws {
        let alerts = MockAlertManager()
        var currentDate = Date(timeIntervalSince1970: 0)
        let store = TimerStore(
            alertManager: alerts,
            nowProvider: { currentDate },
            autoStartTicker: false
        )

        let timerID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 1))
        store.start(timerID)

        currentDate = currentDate.addingTimeInterval(2)
        store.processTick()
        store.processTick()

        XCTAssertEqual(store.timer(for: timerID)?.state, .finished)
        XCTAssertEqual(alerts.finishedTimerIDs, [timerID])
    }

    func testRestartAllResetsAndRunsEveryTimer() throws {
        let alerts = MockAlertManager()
        var currentDate = Date(timeIntervalSince1970: 0)
        let store = TimerStore(
            alertManager: alerts,
            nowProvider: { currentDate },
            autoStartTicker: false
        )

        let firstID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))
        let secondID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 1, seconds: 0))

        store.startAll()
        currentDate = currentDate.addingTimeInterval(5)
        store.processTick()
        store.restartAll()

        XCTAssertEqual(store.timer(for: firstID)?.state, .running)
        XCTAssertEqual(store.timer(for: secondID)?.state, .running)
        XCTAssertEqual(store.timer(for: firstID)?.remainingWholeSeconds, 20)
        XCTAssertEqual(store.timer(for: secondID)?.remainingWholeSeconds, 60)
    }

    func testFloatingOpacityClampsToAllowedRange() {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            floatingOpacity: 3,
            autoStartTicker: false
        )

        XCTAssertEqual(store.floatingOpacity, 1.0)

        store.setFloatingOpacity(0.05)
        XCTAssertEqual(store.floatingOpacity, 0.2)
    }

    func testCreateGroupAllowsSharedControlAndUngroup() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let firstID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 1, seconds: 20))
        let secondID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))

        let groupID = try XCTUnwrap(store.createGroup(with: [firstID, secondID]))
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.group(containing: firstID)?.id, groupID)
        XCTAssertEqual(store.group(containing: secondID)?.id, groupID)

        store.startGroup(groupID)
        XCTAssertEqual(store.timer(for: firstID)?.state, .running)
        XCTAssertEqual(store.timer(for: secondID)?.state, .running)

        store.ungroup(groupID)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNil(store.group(containing: firstID))
        XCTAssertNil(store.group(containing: secondID))
    }

    func testRemovingTimerDissolvesSingleMemberGroup() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let firstID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 1, seconds: 20))
        let secondID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))

        _ = try XCTUnwrap(store.createGroup(with: [firstID, secondID]))
        store.removeTimer(firstID)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNotNil(store.timer(for: secondID))
    }

    func testFloatingHUDVisibilityCanToggleWithoutChangingTimerState() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let timerID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))
        store.start(timerID)

        XCTAssertTrue(store.areFloatingHUDsVisible)
        store.setFloatingHUDsVisible(false)

        XCTAssertFalse(store.areFloatingHUDsVisible)
        XCTAssertEqual(store.timer(for: timerID)?.state, .running)

        store.toggleFloatingHUDsVisibility()
        XCTAssertTrue(store.areFloatingHUDsVisible)
    }

    func testControlPanelModeAndRestoreAllFloatingUI() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let timerID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))
        let secondID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 40))
        let groupID = try XCTUnwrap(store.createGroup(with: [timerID, secondID]))

        store.setControlPanelMode(.minimized)
        store.minimizeGroupHUD(groupID)
        store.setFloatingHUDsVisible(false)

        XCTAssertEqual(store.controlPanelMode, .minimized)
        XCTAssertTrue(store.minimizedGroupIDs.contains(groupID))
        XCTAssertFalse(store.areFloatingHUDsVisible)

        store.restoreAllFloatingUI()

        XCTAssertEqual(store.controlPanelMode, .minimized)
        XCTAssertTrue(store.areFloatingHUDsVisible)
        XCTAssertTrue(store.minimizedGroupIDs.isEmpty)
    }

    func testFloatingCaptureExclusionIsEnabledByDefault() {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        XCTAssertTrue(store.isFloatingCaptureExcluded)
        XCTAssertEqual(store.controlPanelMode, .hidden)
    }

    func testMemoLifecycleAndRestoreAllFloatingUI() throws {
        let alerts = MockAlertManager()
        var currentDate = Date(timeIntervalSince1970: 100)
        let store = TimerStore(
            alertManager: alerts,
            nowProvider: { currentDate },
            autoStartTicker: false
        )

        let memoID = store.addMemo(text: "초기 메모")
        XCTAssertEqual(store.memos.count, 1)
        XCTAssertEqual(store.memo(for: memoID)?.displayTitle, "초기 메모")

        currentDate = currentDate.addingTimeInterval(12)
        store.updateMemoText(memoID, text: "수정된 메모")
        XCTAssertEqual(store.memo(for: memoID)?.instructionText, "수정된 메모")
        XCTAssertEqual(store.memo(for: memoID)?.updatedAt, currentDate)

        store.minimizeMemoHUD(memoID)
        store.setFloatingHUDsVisible(false)
        XCTAssertTrue(store.minimizedMemoIDs.contains(memoID))

        store.restoreAllFloatingUI()
        XCTAssertTrue(store.areFloatingHUDsVisible)
        XCTAssertFalse(store.minimizedMemoIDs.contains(memoID))
    }

    func testRemovingMemoCleansMinimizedState() {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let memoID = store.addMemo(text: "")
        store.minimizeMemoHUD(memoID)
        XCTAssertTrue(store.minimizedMemoIDs.contains(memoID))

        store.removeMemo(memoID)

        XCTAssertTrue(store.memos.isEmpty)
        XCTAssertFalse(store.minimizedMemoIDs.contains(memoID))
    }

    func testAISettingsLoadAndPersist() {
        let settingsStore = InMemoryAISettingsStore(
            snapshot: AISettingsSnapshot(
                provider: .gemini,
                openAIModel: "gpt-test",
                geminiModel: "gemini-test",
                openAIAPIKey: "openai-key",
                geminiAPIKey: "gemini-key"
            )
        )

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            settingsStore: settingsStore
        )

        XCTAssertEqual(store.aiProvider, .gemini)
        XCTAssertEqual(store.openAIModel, "gpt-test")
        XCTAssertEqual(store.geminiModel, "gemini-test")
        XCTAssertEqual(store.openAIAPIKey, "openai-key")
        XCTAssertEqual(store.geminiAPIKey, "gemini-key")

        store.setAIProvider(.openAI)
        store.setOpenAIModel("gpt-next")
        store.setGeminiAPIKey("gemini-next")
        store.setSelectedGeminiKeySlot(3)
        store.setGeminiAPIKey("gemini-slot-4")

        let persisted = settingsStore.load()
        XCTAssertEqual(persisted.provider, .openAI)
        XCTAssertEqual(persisted.openAIModel, "gpt-next")
        XCTAssertEqual(persisted.geminiAPIKeys[0], "gemini-next")
        XCTAssertEqual(persisted.selectedGeminiKeySlot, 3)
        XCTAssertEqual(persisted.geminiAPIKeys[3], "gemini-slot-4")
    }

    func testActiveAIKeySummaryShowsSelectedSlotAndSuffix() {
        let settingsStore = InMemoryAISettingsStore(
            snapshot: AISettingsSnapshot(
                provider: .gemini,
                openAIModel: "gpt-test",
                geminiModel: "gemini-test",
                geminiAPIKeys: ["", "", "AIzaSyDUMMYKEY9876"],
                selectedGeminiKeySlot: 2
            )
        )

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            settingsStore: settingsStore
        )

        XCTAssertEqual(store.activeAIKeySlotNumber, 3)
        XCTAssertEqual(store.activeAIKeySummary, "Gemini 슬롯 3 · ****9876")
    }

    func testCanStoreMultipleAPIKeysPerProvider() {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        store.setOpenAIAPIKey("slot-1-key")
        store.setSelectedOpenAIKeySlot(4)
        store.setOpenAIAPIKey("slot-5-key")

        XCTAssertEqual(store.openAIAPIKey, "slot-5-key")
        XCTAssertEqual(store.filledOpenAIKeySlots, Set([0, 4]))

        store.setSelectedOpenAIKeySlot(0)
        XCTAssertEqual(store.openAIAPIKey, "slot-1-key")
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "FloatingTimersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    func testPersistentAISettingsStoreKeepsKeysOnlyInKeychain() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = InMemoryKeychainStore()

        PersistentAISettingsStore(userDefaults: defaults, keychain: keychain).save(
            AISettingsSnapshot(
                provider: .gemini,
                openAIModel: "gpt-test",
                geminiModel: "gemini-test",
                openAIAPIKeys: ["open-key-1"],
                geminiAPIKeys: ["gemini-key-1", "gemini-key-2"],
                selectedOpenAIKeySlot: 0,
                selectedGeminiKeySlot: 1
            )
        )

        // 평문 키가 UserDefaults 어디에도 남지 않아야 한다.
        let persistedValues = defaults.persistentDomain(forName: suiteName) ?? [:]
        let flattened = persistedValues.values.map { "\($0)" }.joined(separator: "|")
        XCTAssertFalse(flattened.contains("open-key-1"))
        XCTAssertFalse(flattened.contains("gemini-key"))
        XCTAssertEqual(keychain.string(for: "ai.gemini.key.1"), "gemini-key-2")

        let reloaded = PersistentAISettingsStore(userDefaults: defaults, keychain: keychain).load()
        XCTAssertEqual(reloaded.openAIAPIKeys[0], "open-key-1")
        XCTAssertEqual(reloaded.geminiAPIKeys[0], "gemini-key-1")
        XCTAssertEqual(reloaded.geminiAPIKeys[1], "gemini-key-2")
        XCTAssertEqual(reloaded.selectedGeminiKeySlot, 1)
        XCTAssertEqual(reloaded.provider, .gemini)
    }

    func testPersistentAISettingsStoreMigratesLegacyPlaintextKeys() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = InMemoryKeychainStore()
        defaults.set(["legacy-open"], forKey: "ai.openai.keys")
        defaults.set(["", "legacy-gemini"], forKey: "ai.gemini.keys")

        let loaded = PersistentAISettingsStore(userDefaults: defaults, keychain: keychain).load()

        XCTAssertEqual(loaded.openAIAPIKeys[0], "legacy-open")
        XCTAssertEqual(loaded.geminiAPIKeys[1], "legacy-gemini")
        XCTAssertEqual(keychain.string(for: "ai.openai.key.0"), "legacy-open")
        XCTAssertEqual(keychain.string(for: "ai.gemini.key.1"), "legacy-gemini")
        XCTAssertNil(defaults.object(forKey: "ai.openai.keys"))
        XCTAssertNil(defaults.object(forKey: "ai.gemini.keys"))
    }

    func testPersistentAISettingsStoreKeepsLegacyKeysWhenKeychainWriteFails() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = InMemoryKeychainStore()
        keychain.failWrites = true
        defaults.set(["legacy-open"], forKey: "ai.openai.keys")

        let loaded = PersistentAISettingsStore(userDefaults: defaults, keychain: keychain).load()

        // Keychain 저장에 실패하면 키를 잃지 않도록 레거시 값을 유지한다.
        XCTAssertEqual(loaded.openAIAPIKeys[0], "legacy-open")
        XCTAssertEqual(defaults.stringArray(forKey: "ai.openai.keys")?.first, "legacy-open")
    }

    func testPersistentAISettingsStoreMigratesLegacySingleKeychainItem() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = InMemoryKeychainStore()
        keychain.set("old-single", for: "ai.openai.key")

        let loaded = PersistentAISettingsStore(userDefaults: defaults, keychain: keychain).load()

        XCTAssertEqual(loaded.openAIAPIKeys[0], "old-single")
        XCTAssertEqual(keychain.string(for: "ai.openai.key.0"), "old-single")
        XCTAssertNil(keychain.string(for: "ai.openai.key"))
    }

    func testLegacyGeminiModelAliasIsNormalizedOnLoad() {
        let settingsStore = InMemoryAISettingsStore(
            snapshot: AISettingsSnapshot(
                provider: .gemini,
                openAIModel: "gpt-test",
                geminiModel: "gemini-3.0-flash-preview",
                openAIAPIKey: "openai-key",
                geminiAPIKey: "gemini-key"
            )
        )

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            settingsStore: settingsStore
        )

        XCTAssertEqual(store.geminiModel, "gemini-3-flash-preview")
        XCTAssertEqual(settingsStore.load().geminiModel, "gemini-3-flash-preview")
    }

    func testMemoDebugExportIncludesErrorContext() {
        let memo = MemoItem(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            instructionText: "화면 요약해줘",
            imageData: nil,
            imageFilename: nil,
            conversationEntries: [
                MemoConversationEntry(
                    id: UUID(),
                    role: .systemError,
                    createdAt: Date(timeIntervalSince1970: 30),
                    text: "AI 요청 실패 (404): model not found",
                    imageData: nil,
                    imageFilename: nil,
                    isStreaming: false
                ),
            ],
            assistantStatus: .idle,
            lastCapturedImageData: nil,
            lastFocusedAt: nil,
            expandedSize: MemoItem.defaultExpandedSize(hasImage: false),
            fontSize: MemoItem.defaultFontSize,
            tint: .default
        )

        let payload = memo.debugExport(
            providerLabel: "Gemini",
            model: "gemini-3-flash-preview",
            hotkey: "Control + Command + Option + Space",
            errorOnly: true
        )

        XCTAssertTrue(payload.contains("provider: Gemini"))
        XCTAssertTrue(payload.contains("model: gemini-3-flash-preview"))
        XCTAssertTrue(payload.contains("last_error: AI 요청 실패 (404): model not found"))
        XCTAssertTrue(payload.contains("prompt:\n화면 요약해줘"))
        XCTAssertTrue(payload.contains("[ERROR"))
    }

    func testCaptureTargetsFocusedMemoOrCreatesNewOne() async {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            screenCaptureService: MockScreenCaptureService(),
            visionAssistantService: MockVisionAssistantService()
        )

        let firstID = store.addMemo(text: "첫 번째")
        let secondID = store.addMemo(text: "두 번째")
        store.markMemoFocused(firstID)
        store.markMemoFocused(secondID)
        store.setOpenAIAPIKey("test-key")

        await store.captureScreenIntoFocusedMemo()

        XCTAssertEqual(store.focusedMemoID, secondID)
        XCTAssertEqual(store.memo(for: secondID)?.conversationEntries.count, 2)
        XCTAssertEqual(store.memo(for: firstID)?.conversationEntries.count, 0)
    }

    func testPersistedStateRestoresRunningTimerAndPanelOrigins() throws {
        let appStateStore = InMemoryAppStateStore()
        var currentDate = Date(timeIntervalSince1970: 100)

        let firstStore = TimerStore(
            alertManager: MockAlertManager(),
            nowProvider: { currentDate },
            autoStartTicker: false,
            appStateStore: appStateStore
        )

        let timerID = try XCTUnwrap(firstStore.addTimer(hours: 0, minutes: 1, seconds: 20))
        let memoID = firstStore.addMemo(text: "복구 테스트")
        firstStore.start(timerID)
        firstStore.setMemoFontSize(memoID, size: 16)
        firstStore.setFloatingOpacity(0.66)
        firstStore.setControlPanelMode(.minimized)
        firstStore.setTimerPanelOrigin(timerID, origin: CGPoint(x: 140, y: 280))
        firstStore.setMemoPanelOrigin(memoID, origin: CGPoint(x: 220, y: 360))
        firstStore.flushPersistedStateNow()

        currentDate = currentDate.addingTimeInterval(10)

        let restoredStore = TimerStore(
            alertManager: MockAlertManager(),
            nowProvider: { currentDate },
            autoStartTicker: false,
            appStateStore: appStateStore
        )

        XCTAssertEqual(restoredStore.timer(for: timerID)?.state, .running)
        XCTAssertEqual(restoredStore.timer(for: timerID)?.remainingWholeSeconds, 70)
        XCTAssertEqual(restoredStore.floatingOpacity, 0.66, accuracy: 0.001)
        XCTAssertEqual(restoredStore.controlPanelMode, .minimized)
        XCTAssertEqual(restoredStore.timerPanelOrigin(for: timerID), CGPoint(x: 140, y: 280))
        XCTAssertEqual(restoredStore.memoPanelOrigin(for: memoID), CGPoint(x: 220, y: 360))
        XCTAssertEqual(restoredStore.memo(for: memoID)?.fontSize, 16)
    }

    func testInterruptedAssistantRequestRestoresToIdleWithSystemError() {
        let memoID = UUID()
        let snapshot = AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            timers: [],
            groups: [],
            memos: [
                MemoItemSnapshot(
                    id: memoID,
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20),
                    instructionText: "화면을 설명해줘",
                    imageData: nil,
                    imageFilename: nil,
                    conversationEntries: [
                        MemoConversationEntry(
                            id: UUID(),
                            role: .assistant,
                            createdAt: Date(timeIntervalSince1970: 18),
                            text: "partial",
                            imageData: nil,
                            imageFilename: nil,
                            isStreaming: true
                        ),
                    ],
                    assistantStatus: .streaming,
                    lastCapturedImageData: nil,
                    lastFocusedAt: nil,
                    expandedSize: CGSizeSnapshot(CGSize(width: 300, height: 320)),
                    fontSize: 15,
                    tint: .default
                ),
            ],
            floatingOpacity: 0.7,
            areFloatingHUDsVisible: true,
            controlPanelMode: .hidden,
            minimizedTimerIDs: [],
            minimizedGroupIDs: [],
            minimizedMemoIDs: [],
            focusedMemoID: memoID,
            aiConfiguration: AIConfigurationStateSnapshot(
                provider: .gemini,
                openAIModel: "gpt-4.1",
                geminiModel: "gemini-2.5-flash",
                selectedOpenAIKeySlot: 0,
                selectedGeminiKeySlot: 0
            ),
            panelOrigins: FloatingPanelOriginsSnapshot(
                timerOrigins: [],
                groupOrigins: [],
                memoOrigins: [],
                controlPanelOrigin: nil
            )
        )

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            appStateStore: InMemoryAppStateStore(snapshot: snapshot)
        )

        XCTAssertEqual(store.memo(for: memoID)?.assistantStatus, .idle)
        XCTAssertEqual(store.memo(for: memoID)?.latestErrorEntry?.text, "이전 요청이 앱 종료로 중단되었습니다.")
        XCTAssertFalse(store.memo(for: memoID)?.conversationEntries.contains(where: \.isStreaming) ?? true)
        XCTAssertEqual(store.memo(for: memoID)?.fontSize, 15)
    }

    func testSeedDefaultSetupDoesNotRunWhenPersistedEmptyStateExists() {
        let snapshot = AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            timers: [],
            groups: [],
            memos: [],
            floatingOpacity: 0.78,
            areFloatingHUDsVisible: true,
            controlPanelMode: .hidden,
            minimizedTimerIDs: [],
            minimizedGroupIDs: [],
            minimizedMemoIDs: [],
            focusedMemoID: nil,
            aiConfiguration: AIConfigurationStateSnapshot(
                provider: .openAI,
                openAIModel: "gpt-4.1",
                geminiModel: "gemini-2.5-flash",
                selectedOpenAIKeySlot: 0,
                selectedGeminiKeySlot: 0
            ),
            panelOrigins: FloatingPanelOriginsSnapshot(
                timerOrigins: [],
                groupOrigins: [],
                memoOrigins: [],
                controlPanelOrigin: nil
            )
        )

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            appStateStore: InMemoryAppStateStore(snapshot: snapshot)
        )

        store.seedDefaultSetupIfNeeded()

        XCTAssertTrue(store.timers.isEmpty)
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testSendTextPromptAppendsUserAndAssistantEntries() async throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            visionAssistantService: MockVisionAssistantService()
        )

        let memoID = store.addMemo(text: "짧게 답해줘")
        store.setOpenAIAPIKey("test-key")

        await store.sendTextPrompt("안녕?", to: memoID)

        let entries = try XCTUnwrap(store.memo(for: memoID)?.conversationEntries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].role, .userPrompt)
        XCTAssertEqual(entries[0].text, "안녕?")
        XCTAssertEqual(entries[1].role, .assistant)
        XCTAssertEqual(entries[1].text, "mock response")
    }

    func testSendTextPromptFallsBackToNextKeySlot() async throws {
        let settingsStore = InMemoryAISettingsStore(
            snapshot: AISettingsSnapshot(
                provider: .gemini,
                openAIModel: "gpt-test",
                geminiModel: "gemini-test",
                geminiAPIKeys: ["bad-key", "good-key"],
                selectedGeminiKeySlot: 0
            )
        )
        let recorder = AttemptRecorder()
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            settingsStore: settingsStore,
            visionAssistantService: MockVisionAssistantService(
                handler: { provider, _, apiKey, _, _, _ in
                    guard provider == .gemini else {
                        throw VisionAssistantError.serviceError("wrong provider")
                    }

                    await recorder.append(apiKey)

                    if apiKey == "bad-key" {
                        throw VisionAssistantError.httpError(400, "Gemini API 키가 유효하지 않습니다. 선택한 키 슬롯을 다시 확인하세요.")
                    }

                    return "fallback response"
                }
            )
        )

        let memoID = store.addMemo(text: "테스트")

        await store.sendTextPrompt("안녕?", to: memoID)

        let entries = try XCTUnwrap(store.memo(for: memoID)?.conversationEntries)
        let attemptedKeys = await recorder.valuesSnapshot()
        XCTAssertEqual(attemptedKeys, ["bad-key", "good-key"])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[1].role, .assistant)
        XCTAssertEqual(entries[1].text, "fallback response")
        XCTAssertEqual(store.selectedGeminiKeySlot, 1)
        XCTAssertEqual(settingsStore.load().selectedGeminiKeySlot, 1)
    }

    func testAssistantResponseIsSavedToLocalTextFile() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FloatingTimersTests-\(UUID().uuidString)", isDirectory: true)
        let transcriptStore = FileMemoTranscriptStore(applicationSupportURL: tempDirectory)

        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false,
            visionAssistantService: MockVisionAssistantService(),
            memoTranscriptStore: transcriptStore
        )

        let memoID = store.addMemo(text: "저장 테스트")
        store.setOpenAIAPIKey("test-key")

        await store.sendTextPrompt("안녕?", to: memoID)

        let fileURL = tempDirectory
            .appendingPathComponent("FloatingTimers", isDirectory: true)
            .appendingPathComponent("memo_answers", isDirectory: true)
            .appendingPathComponent("\(memoID.uuidString).txt", isDirectory: false)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("# 저장 테스트"))
        XCTAssertTrue(contents.contains("mock response"))
    }

    func testGroupingAndRemovalCleanUpMinimizedFloatingState() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let firstID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 1, seconds: 20))
        let secondID = try XCTUnwrap(store.addTimer(hours: 0, minutes: 0, seconds: 20))

        store.minimizeTimerHUD(firstID)
        XCTAssertTrue(store.minimizedTimerIDs.contains(firstID))

        let groupID = try XCTUnwrap(store.createGroup(with: [firstID, secondID]))
        XCTAssertFalse(store.minimizedTimerIDs.contains(firstID))

        store.minimizeGroupHUD(groupID)
        XCTAssertTrue(store.minimizedGroupIDs.contains(groupID))

        store.ungroup(groupID)
        XCTAssertFalse(store.minimizedGroupIDs.contains(groupID))

        store.minimizeTimerHUD(secondID)
        store.removeTimer(secondID)
        XCTAssertFalse(store.minimizedTimerIDs.contains(secondID))
    }

    func testMemoTintCanBeUpdated() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let memoID = store.addMemo(text: "색상 메모")
        let tint = MemoTint(red: 0.12, green: 0.34, blue: 0.56, alpha: 1)
        store.setMemoTint(memoID, tint: tint)

        XCTAssertEqual(store.memo(for: memoID)?.tint, tint)
    }

    func testMemoFontSizeCanBeUpdated() {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        let memoID = store.addMemo(text: "글씨 크기")
        store.setMemoFontSize(memoID, size: 17)
        XCTAssertEqual(store.memo(for: memoID)?.fontSize, 17)

        store.setMemoFontSize(memoID, size: 40)
        XCTAssertEqual(store.memo(for: memoID)?.fontSize, MemoItem.maximumFontSize)
    }

    func testSeedDefaultSetupCreatesGroupedPresetTimers() throws {
        let store = TimerStore(
            alertManager: MockAlertManager(),
            autoStartTicker: false
        )

        store.seedDefaultSetupIfNeeded()

        XCTAssertEqual(store.timers.count, 2)
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.timers.map(\.remainingWholeSeconds), [80, 20])

        let group = try XCTUnwrap(store.groups.first)
        XCTAssertEqual(group.timerIDs.count, 2)
    }
}

@MainActor
private final class MockAlertManager: TimerAlerting {
    var finishedTimerIDs: [UUID] = []

    func requestAuthorizationIfNeeded() async {}

    func notifyTimerFinished(_ timer: TimerItem) {
        finishedTimerIDs.append(timer.id)
    }
}

private struct MockScreenCaptureService: ScreenCaptureServing {
    @MainActor
    func captureCurrentScreenJPEG() async throws -> CapturedScreenshot {
        CapturedScreenshot(data: Data("image".utf8), filename: "mock.jpg", mimeType: "image/jpeg")
    }
}

private struct MockVisionAssistantService: VisionAssistantStreaming {
    let handler: @Sendable (AIProvider, String, String, String, Data?, String?) async throws -> String

    init(
        handler: @escaping @Sendable (AIProvider, String, String, String, Data?, String?) async throws -> String = { _, _, _, _, _, _ in
            "mock response"
        }
    ) {
        self.handler = handler
    }

    func streamResponse(
        provider: AIProvider,
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data?,
        mimeType: String?,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        onDelta(try await handler(provider, model, apiKey, prompt, imageData, mimeType))
    }
}

private actor AttemptRecorder {
    private var storage: [String] = []

    func append(_ value: String) {
        storage.append(value)
    }

    func valuesSnapshot() -> [String] {
        storage
    }
}

private final class InMemoryKeychainStore: KeychainStoring {
    private var storage: [String: String] = [:]

    func string(for account: String) -> String? {
        storage[account]
    }

    var failWrites = false

    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        guard !failWrites else {
            return false
        }
        if value.isEmpty {
            storage.removeValue(forKey: account)
        } else {
            storage[account] = value
        }
        return true
    }
}
