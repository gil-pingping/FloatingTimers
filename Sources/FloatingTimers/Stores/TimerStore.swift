import AppKit
import Combine
import Foundation
import CoreGraphics

@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var timers: [TimerItem] = []
    @Published private(set) var groups: [TimerGroup] = []
    @Published private(set) var memos: [MemoItem] = []
    @Published private(set) var floatingOpacity: Double
    @Published private(set) var areFloatingHUDsVisible: Bool
    @Published private(set) var isFloatingCaptureExcluded: Bool
    @Published private(set) var controlPanelMode: FloatingPanelMode
    @Published private(set) var minimizedTimerIDs: Set<UUID>
    @Published private(set) var minimizedGroupIDs: Set<UUID>
    @Published private(set) var minimizedMemoIDs: Set<UUID>
    @Published private(set) var focusedMemoID: UUID?
    @Published private(set) var aiProvider: AIProvider
    @Published private(set) var openAIModel: String
    @Published private(set) var geminiModel: String
    @Published private(set) var openAIAPIKeys: [String]
    @Published private(set) var geminiAPIKeys: [String]
    @Published private(set) var selectedOpenAIKeySlot: Int
    @Published private(set) var selectedGeminiKeySlot: Int
    @Published private(set) var aiSmokeStatus: String
    @Published private(set) var timerPanelOrigins: [UUID: CGPoint]
    @Published private(set) var groupPanelOrigins: [UUID: CGPoint]
    @Published private(set) var memoPanelOrigins: [UUID: CGPoint]
    @Published private(set) var controlPanelOrigin: CGPoint?
    @Published private(set) var persistenceStatusMessage: String

    private let alertManager: TimerAlerting
    private let nowProvider: () -> Date
    private let settingsStore: AISettingsPersisting
    private let appStateStore: AppStatePersisting
    private let screenCaptureService: ScreenCaptureServing
    private let visionAssistantService: VisionAssistantStreaming
    private let memoTranscriptStore: MemoTranscriptPersisting
    private var ticker: Timer?
    private var nextTimerNumber = 1
    private var nextGroupNumber = 1
    private var pendingStateSaveWorkItem: DispatchWorkItem?
    private var activeAITasks: [UUID: Task<Void, Never>] = [:]
    private var hasLoadedPersistedState = false
    private var isRestoringPersistedState = false

    init(
        alertManager: TimerAlerting,
        nowProvider: @escaping () -> Date = Date.init,
        floatingOpacity: Double = 0.78,
        areFloatingHUDsVisible: Bool = true,
        controlPanelMode: FloatingPanelMode = .hidden,
        autoStartTicker: Bool = true,
        settingsStore: AISettingsPersisting = InMemoryAISettingsStore(),
        appStateStore: AppStatePersisting = InMemoryAppStateStore(),
        screenCaptureService: ScreenCaptureServing = UnavailableScreenCaptureService(),
        visionAssistantService: VisionAssistantStreaming = UnavailableVisionAssistantService(),
        memoTranscriptStore: MemoTranscriptPersisting = InMemoryMemoTranscriptStore()
    ) {
        let loadedSettings = settingsStore.load()
        let settingsSnapshot = Self.normalizedSettings(loadedSettings)
        self.alertManager = alertManager
        self.nowProvider = nowProvider
        self.settingsStore = settingsStore
        self.appStateStore = appStateStore
        self.screenCaptureService = screenCaptureService
        self.visionAssistantService = visionAssistantService
        self.memoTranscriptStore = memoTranscriptStore
        self.floatingOpacity = Self.clampedOpacity(floatingOpacity)
        self.areFloatingHUDsVisible = areFloatingHUDsVisible
        isFloatingCaptureExcluded = true
        self.controlPanelMode = controlPanelMode
        minimizedTimerIDs = []
        minimizedGroupIDs = []
        minimizedMemoIDs = []
        focusedMemoID = nil
        aiProvider = settingsSnapshot.provider
        openAIModel = settingsSnapshot.openAIModel
        geminiModel = settingsSnapshot.geminiModel
        openAIAPIKeys = settingsSnapshot.openAIAPIKeys
        geminiAPIKeys = settingsSnapshot.geminiAPIKeys
        selectedOpenAIKeySlot = settingsSnapshot.selectedOpenAIKeySlot
        selectedGeminiKeySlot = settingsSnapshot.selectedGeminiKeySlot
        aiSmokeStatus = "아직 스모크 테스트를 실행하지 않았습니다."
        timerPanelOrigins = [:]
        groupPanelOrigins = [:]
        memoPanelOrigins = [:]
        controlPanelOrigin = nil
        persistenceStatusMessage = "저장 상태 없음"

        if settingsSnapshot != loadedSettings {
            settingsStore.save(settingsSnapshot)
        }

        restorePersistedAppStateIfAvailable()

        if autoStartTicker {
            startTicker()
        }
    }

    func prepareAlerts() async {
        await alertManager.requestAuthorizationIfNeeded()
    }

    func seedDefaultSetupIfNeeded() {
        guard !hasLoadedPersistedState else {
            return
        }

        guard timers.isEmpty, groups.isEmpty else {
            return
        }

        guard
            let longTimerID = addTimer(hours: 0, minutes: 1, seconds: 20),
            let shortTimerID = addTimer(hours: 0, minutes: 0, seconds: 20)
        else {
            return
        }

        _ = createGroup(with: [longTimerID, shortTimerID])
    }

    @discardableResult
    func addTimer(hours: Int, minutes: Int, seconds: Int) -> UUID? {
        let normalizedHours = max(hours, 0)
        let normalizedMinutes = max(minutes, 0)
        let normalizedSeconds = max(seconds, 0)
        let totalSeconds = normalizedHours * 3600 + normalizedMinutes * 60 + normalizedSeconds

        guard totalSeconds > 0 else {
            return nil
        }

        let timer = TimerItem(
            id: UUID(),
            name: "타이머 \(nextTimerNumber)",
            configuredDurationText: DurationFormatter.koreanLabel(totalSeconds: totalSeconds),
            createdAt: nowProvider(),
            initialDuration: TimeInterval(totalSeconds),
            remainingDuration: TimeInterval(totalSeconds),
            state: .idle,
            endDate: nil
        )

        nextTimerNumber += 1
        timers.append(timer)
        scheduleStateSave()
        return timer.id
    }

    func renameTimer(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard timers[index].name != trimmed else {
            return
        }

        timers[index].name = trimmed
        scheduleStateSave()
    }

    func updateTimerDuration(_ id: UUID, hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = max(hours, 0) * 3600 + max(minutes, 0) * 60 + max(seconds, 0)
        guard totalSeconds > 0 else {
            return
        }

        updateTimer(id) { timer, _ in
            guard timer.state == .idle || timer.state == .paused else {
                return
            }

            timer.remainingDuration = TimeInterval(totalSeconds)
            timer.state = .idle
            timer.endDate = nil
        }
    }

    func timer(for id: UUID) -> TimerItem? {
        timers.first(where: { $0.id == id })
    }

    func group(for id: UUID) -> TimerGroup? {
        groups.first(where: { $0.id == id })
    }

    func memo(for id: UUID) -> MemoItem? {
        memos.first(where: { $0.id == id })
    }

    func group(containing timerID: UUID) -> TimerGroup? {
        groups.first(where: { $0.timerIDs.contains(timerID) })
    }

    func timers(inGroup id: UUID) -> [TimerItem] {
        guard let group = group(for: id) else {
            return []
        }

        let timersByID = Dictionary(uniqueKeysWithValues: timers.map { ($0.id, $0) })
        return group.timerIDs.compactMap { timersByID[$0] }
    }

    func containsTimer(with id: UUID) -> Bool {
        timers.contains(where: { $0.id == id })
    }

    var groupedTimerIDs: Set<UUID> {
        Set(groups.flatMap(\.timerIDs))
    }

    var activeFloatingTimerIDs: [UUID] {
        let groupedTimerIDs = groupedTimerIDs
        return timers.map(\.id).filter { !groupedTimerIDs.contains($0) }
    }

    var activeFloatingGroupIDs: [UUID] {
        groups.map(\.id)
    }

    var activeFloatingMemoIDs: [UUID] {
        memos.map(\.id)
    }

    var activeAIModel: String {
        switch aiProvider {
        case .openAI:
            return openAIModel
        case .gemini:
            return geminiModel
        }
    }

    var activeAIAPIKey: String {
        guard let slot = preferredDisplayKeySlot(for: aiProvider) else {
            return ""
        }

        switch aiProvider {
        case .openAI:
            return Self.key(at: slot, in: openAIAPIKeys)
        case .gemini:
            return Self.key(at: slot, in: geminiAPIKeys)
        }
    }

    var openAIAPIKey: String {
        Self.key(at: selectedOpenAIKeySlot, in: openAIAPIKeys)
    }

    var geminiAPIKey: String {
        Self.key(at: selectedGeminiKeySlot, in: geminiAPIKeys)
    }

    var filledOpenAIKeySlots: Set<Int> {
        Self.filledKeySlots(in: openAIAPIKeys)
    }

    var filledGeminiKeySlots: Set<Int> {
        Self.filledKeySlots(in: geminiAPIKeys)
    }

    var aiHotkeyDescription: String {
        GlobalHotkeyManager.hotkeyDescription
    }

    var aiConfigurationSummary: String {
        let model = activeAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyState = hasActiveAIKey ? "ready" : "API key 필요"
        let slot = activeAIKeySlotNumber
        return "\(aiProvider.label) · \(model.isEmpty ? "model 필요" : model) · slot \(slot) · \(keyState)"
    }

    var hasActiveAIKey: Bool {
        !availableKeyCandidates(for: aiProvider).isEmpty
    }

    var activeAIKeySlotNumber: Int {
        (preferredDisplayKeySlot(for: aiProvider) ?? currentSelectedKeySlot(for: aiProvider)) + 1
    }

    var activeAIKeySummary: String {
        let trimmedKey = activeAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return "\(aiProvider.label) 슬롯 \(activeAIKeySlotNumber) · 키 없음"
        }

        let suffixLength = min(4, trimmedKey.count)
        let suffix = String(trimmedKey.suffix(suffixLength))
        return "\(aiProvider.label) 슬롯 \(activeAIKeySlotNumber) · ****\(suffix)"
    }

    var screenCapturePermissionSummary: String {
        CGPreflightScreenCaptureAccess() ? "허용됨" : "권한 필요"
    }

    var recentAIErrorSummary: String {
        let latestError = memos
            .compactMap { memo in
                memo.latestErrorEntry.map { ($0.createdAt, $0.text) }
            }
            .max(by: { $0.0 < $1.0 })?
            .1
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let latestError, !latestError.isEmpty {
            return latestError
        }

        return "최근 AI 오류 없음"
    }

    var floatingRecoverySummary: String {
        if !areFloatingHUDsVisible {
            return "플로팅 HUD 꺼짐"
        }

        if minimizedFloatingHUDCount > 0 {
            return "접힌 카드 \(minimizedFloatingHUDCount)개"
        }

        return "플로팅 정상"
    }

    var totalFloatingHUDCount: Int {
        activeFloatingTimerIDs.count + activeFloatingGroupIDs.count + activeFloatingMemoIDs.count
    }

    var minimizedFloatingHUDCount: Int {
        minimizedTimerIDs.count + minimizedGroupIDs.count + minimizedMemoIDs.count
    }

    var displayedFloatingHUDCount: Int {
        guard areFloatingHUDsVisible else {
            return 0
        }

        return max(totalFloatingHUDCount - minimizedFloatingHUDCount, 0)
    }

    func setFloatingOpacity(_ opacity: Double) {
        floatingOpacity = Self.clampedOpacity(opacity)
        scheduleStateSave()
    }

    func setFloatingHUDsVisible(_ isVisible: Bool) {
        areFloatingHUDsVisible = isVisible
        scheduleStateSave()
    }

    func toggleFloatingHUDsVisibility() {
        areFloatingHUDsVisible.toggle()
        scheduleStateSave()
    }

    func setControlPanelMode(_ mode: FloatingPanelMode) {
        controlPanelMode = mode
        scheduleStateSave()
    }

    func minimizeTimerHUD(_ id: UUID) {
        guard containsTimer(with: id), group(containing: id) == nil else {
            return
        }

        minimizedTimerIDs.insert(id)
        scheduleStateSave()
    }

    func restoreTimerHUD(_ id: UUID) {
        minimizedTimerIDs.remove(id)
        scheduleStateSave()
    }

    func minimizeGroupHUD(_ id: UUID) {
        guard group(for: id) != nil else {
            return
        }

        minimizedGroupIDs.insert(id)
        scheduleStateSave()
    }

    func restoreGroupHUD(_ id: UUID) {
        minimizedGroupIDs.remove(id)
        scheduleStateSave()
    }

    func restoreAllFloatingUI() {
        areFloatingHUDsVisible = true
        minimizedTimerIDs.removeAll()
        minimizedGroupIDs.removeAll()
        minimizedMemoIDs.removeAll()
        scheduleStateSave()
    }

    func setAIProvider(_ provider: AIProvider) {
        aiProvider = provider
        persistAISettings()
        scheduleStateSave()
    }

    func setOpenAIModel(_ model: String) {
        openAIModel = Self.normalizedModel(provider: .openAI, model: model)
        persistAISettings()
        scheduleStateSave()
    }

    func setGeminiModel(_ model: String) {
        geminiModel = Self.normalizedModel(provider: .gemini, model: model)
        persistAISettings()
        scheduleStateSave()
    }

    func setOpenAIAPIKey(_ key: String) {
        let slot = Self.clampedKeySlot(selectedOpenAIKeySlot)
        openAIAPIKeys[slot] = key
        persistAISettings()
        scheduleStateSave()
    }

    func setGeminiAPIKey(_ key: String) {
        let slot = Self.clampedKeySlot(selectedGeminiKeySlot)
        geminiAPIKeys[slot] = key
        persistAISettings()
        scheduleStateSave()
    }

    func setSelectedOpenAIKeySlot(_ slot: Int) {
        selectedOpenAIKeySlot = Self.clampedKeySlot(slot)
        persistAISettings()
        scheduleStateSave()
    }

    func setSelectedGeminiKeySlot(_ slot: Int) {
        selectedGeminiKeySlot = Self.clampedKeySlot(slot)
        persistAISettings()
        scheduleStateSave()
    }

    func runTextOnlyAISmokeTest() {
        Task { @MainActor in
            await performTextOnlyAISmokeTest()
        }
    }

    func runCaptureOnlySmokeTest() {
        Task { @MainActor in
            await performCaptureOnlySmokeTest()
        }
    }

    func runCaptureAISmokeTest() {
        Task { @MainActor in
            await performCaptureAISmokeTest()
        }
    }

    func timerPanelOrigin(for id: UUID) -> CGPoint? {
        timerPanelOrigins[id]
    }

    func groupPanelOrigin(for id: UUID) -> CGPoint? {
        groupPanelOrigins[id]
    }

    func memoPanelOrigin(for id: UUID) -> CGPoint? {
        memoPanelOrigins[id]
    }

    func setTimerPanelOrigin(_ id: UUID, origin: CGPoint) {
        guard timerPanelOrigins[id] != origin else {
            return
        }

        timerPanelOrigins[id] = origin
        scheduleStateSave()
    }

    func setGroupPanelOrigin(_ id: UUID, origin: CGPoint) {
        guard groupPanelOrigins[id] != origin else {
            return
        }

        groupPanelOrigins[id] = origin
        scheduleStateSave()
    }

    func setMemoPanelOrigin(_ id: UUID, origin: CGPoint) {
        guard memoPanelOrigins[id] != origin else {
            return
        }

        memoPanelOrigins[id] = origin
        scheduleStateSave()
    }

    func setControlPanelOrigin(_ origin: CGPoint) {
        guard controlPanelOrigin != origin else {
            return
        }

        controlPanelOrigin = origin
        scheduleStateSave()
    }

    @discardableResult
    func addMemo(text: String = "", imageData: Data? = nil, imageFilename: String? = nil) -> UUID {
        let hasImage = imageData != nil
        let memo = MemoItem(
            id: UUID(),
            createdAt: nowProvider(),
            updatedAt: nowProvider(),
            instructionText: text,
            imageData: imageData,
            imageFilename: imageFilename,
            conversationEntries: [],
            assistantStatus: .idle,
            lastCapturedImageData: nil,
            lastFocusedAt: nil,
            expandedSize: MemoItem.defaultExpandedSize(hasImage: hasImage),
            fontSize: MemoItem.defaultFontSize,
            tint: .default
        )

        memos.append(memo)
        scheduleStateSave()
        return memo.id
    }

    func updateMemoInstruction(_ id: UUID, text: String) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard memos[index].instructionText != text else {
            return
        }

        memos[index].instructionText = text
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func updateMemoText(_ id: UUID, text: String) {
        updateMemoInstruction(id, text: text)
    }

    func markMemoFocused(_ id: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        let now = nowProvider()
        memos[index].lastFocusedAt = now
        memos[index].updatedAt = now
        focusedMemoID = id
        scheduleStateSave()
    }

    func setMemoImage(_ id: UUID, imageData: Data?, imageFilename: String? = nil) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        memos[index].imageData = imageData
        memos[index].imageFilename = imageData == nil ? nil : imageFilename
        memos[index].expandedSize = MemoItem.clampedExpandedSize(
            memos[index].expandedSize,
            hasImage: imageData != nil
        )
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func setMemoTint(_ id: UUID, tint: MemoTint) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard memos[index].tint != tint else {
            return
        }

        memos[index].tint = tint
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func resizeMemo(_ id: UUID, to proposedSize: CGSize) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        let clampedSize = MemoItem.clampedExpandedSize(proposedSize, hasImage: memos[index].hasImage)
        guard memos[index].expandedSize != clampedSize else {
            return
        }

        memos[index].expandedSize = clampedSize
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func setMemoFontSize(_ id: UUID, size: CGFloat) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        let clampedSize = MemoItem.clampedFontSize(size)
        guard memos[index].fontSize != clampedSize else {
            return
        }

        memos[index].fontSize = clampedSize
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func increaseMemoFontSize(_ id: UUID) {
        guard let memo = memo(for: id) else {
            return
        }

        setMemoFontSize(id, size: memo.fontSize + 1)
    }

    func decreaseMemoFontSize(_ id: UUID) {
        guard let memo = memo(for: id) else {
            return
        }

        setMemoFontSize(id, size: memo.fontSize - 1)
    }

    func removeMemoImage(_ id: UUID) {
        setMemoImage(id, imageData: nil)
    }

    func clearMemoConversation(_ id: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else {
            return
        }

        cancelAIRequest(for: id)
        memos[index].conversationEntries.removeAll()
        memos[index].assistantStatus = .idle
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    func removeMemo(_ id: UUID) {
        cancelAIRequest(for: id)
        memos.removeAll(where: { $0.id == id })
        if focusedMemoID == id {
            focusedMemoID = memos
                .sorted { ($0.lastFocusedAt ?? $0.createdAt) > ($1.lastFocusedAt ?? $1.createdAt) }
                .first?
                .id
        }
        cleanupFloatingUIState()
        scheduleStateSave()
    }

    func minimizeMemoHUD(_ id: UUID) {
        guard memo(for: id) != nil else {
            return
        }

        minimizedMemoIDs.insert(id)
        scheduleStateSave()
    }

    func restoreMemoHUD(_ id: UUID) {
        minimizedMemoIDs.remove(id)
        scheduleStateSave()
    }

    func revealMemo(_ id: UUID) {
        guard memo(for: id) != nil else {
            return
        }

        setFloatingHUDsVisible(true)
        restoreMemoHUD(id)
        markMemoFocused(id)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusFloatingMemoPanel, object: id)
        }
    }

    func handleCaptureHotkey() {
        let targetMemoID = resolvedTargetMemoIDForAI()
        let task = Task { @MainActor [weak self] in
            await self?.captureScreenIntoFocusedMemo()
            self?.activeAITasks[targetMemoID] = nil
        }
        activeAITasks[targetMemoID] = task
    }

    func submitTextPrompt(_ text: String, to memoID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let task = Task { @MainActor [weak self] in
            await self?.sendTextPrompt(trimmed, to: memoID)
            self?.activeAITasks[memoID] = nil
        }
        activeAITasks[memoID] = task
    }

    func sendTextPrompt(_ text: String, to memoID: UUID) async {
        revealMemo(memoID)

        guard memo(for: memoID) != nil else {
            return
        }

        let requestPrompt = composedPrompt(for: memoID, userText: text)
        await requestAssistantResponse(
            memoID: memoID,
            userEntry: MemoConversationEntry(
                id: UUID(),
                role: .userPrompt,
                createdAt: nowProvider(),
                text: text,
                imageData: nil,
                imageFilename: nil,
                isStreaming: false
            ),
            requestPrompt: requestPrompt,
            imageData: nil,
            imageFilename: nil,
            mimeType: nil
        )
    }

    func cancelAIRequest(for memoID: UUID) {
        guard let task = activeAITasks[memoID] else { return }
        task.cancel()
        activeAITasks[memoID] = nil
        removeEmptyStreamingAssistantEntry(from: memoID)
        setMemoAssistantStatus(.idle, for: memoID)
        appendSystemError("AI 요청이 취소되었습니다.", to: memoID)
    }

    func captureScreenIntoFocusedMemo() async {
        let targetMemoID = resolvedTargetMemoIDForAI()
        revealMemo(targetMemoID)

        guard let memo = memo(for: targetMemoID) else {
            return
        }

        guard memo.assistantStatus == .idle else {
            appendSystemError("이미 이 메모에서 다른 요청이 진행 중입니다.", to: targetMemoID)
            return
        }

        let model = activeAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            appendSystemError("\(aiProvider.label) 모델명이 비어 있습니다.", to: targetMemoID)
            return
        }

        guard hasActiveAIKey else {
            appendSystemError("\(aiProvider.label) API 키가 비어 있습니다.", to: targetMemoID)
            return
        }

        setMemoAssistantStatus(.capturing, for: targetMemoID)

        do {
            let screenshot = try await screenCaptureService.captureCurrentScreenJPEG()
            recordCapturedImage(screenshot.data, for: targetMemoID)

            let prompt = resolvedPrompt(for: targetMemoID)

            await requestAssistantResponse(
                memoID: targetMemoID,
                userEntry: MemoConversationEntry(
                    id: UUID(),
                    role: .userCapture,
                    createdAt: nowProvider(),
                    text: prompt,
                    imageData: screenshot.data,
                    imageFilename: screenshot.filename,
                    isStreaming: false
                ),
                requestPrompt: prompt,
                imageData: screenshot.data,
                imageFilename: screenshot.filename,
                mimeType: screenshot.mimeType
            )
        } catch {
            handleAssistantFailure(error, memoID: targetMemoID)
        }
    }

    @discardableResult
    func createGroup(with timerIDs: [UUID]) -> UUID? {
        let selectedSet = Set(timerIDs)
        let orderedTimerIDs = timers.map(\.id).filter { selectedSet.contains($0) }

        guard orderedTimerIDs.count > 1 else {
            return nil
        }

        var updatedGroups = groups.map { group in
            var updatedGroup = group
            updatedGroup.timerIDs.removeAll(where: selectedSet.contains(_:))
            return updatedGroup
        }

        updatedGroups = normalizedGroups(updatedGroups)

        let newGroup = TimerGroup(
            id: UUID(),
            name: "묶음 \(nextGroupNumber)",
            createdAt: nowProvider(),
            timerIDs: orderedTimerIDs
        )

        nextGroupNumber += 1
        updatedGroups.append(newGroup)
        groups = updatedGroups
        cleanupFloatingUIState()
        scheduleStateSave()
        return newGroup.id
    }

    func ungroup(_ groupID: UUID) {
        groups.removeAll(where: { $0.id == groupID })
        cleanupFloatingUIState()
        scheduleStateSave()
    }

    func start(_ id: UUID) {
        updateTimer(id) { timer, now in
            guard timer.state != .running, timer.remainingDuration > 0 else {
                return
            }

            timer.state = .running
            timer.endDate = now.addingTimeInterval(timer.remainingDuration)
        }
    }

    func pause(_ id: UUID) {
        updateTimer(id) { timer, now in
            guard timer.state == .running, let endDate = timer.endDate else {
                return
            }

            timer.remainingDuration = max(endDate.timeIntervalSince(now), 0)
            timer.endDate = nil
            timer.state = timer.remainingDuration == 0 ? .finished : .paused
        }
    }

    func reset(_ id: UUID) {
        updateTimer(id) { timer, _ in
            timer.remainingDuration = timer.initialDuration
            timer.endDate = nil
            timer.state = .idle
        }
    }

    func restart(_ id: UUID) {
        updateTimer(id) { timer, now in
            timer.remainingDuration = timer.initialDuration
            timer.state = .running
            timer.endDate = now.addingTimeInterval(timer.initialDuration)
        }
    }

    func removeTimer(_ id: UUID) {
        timers.removeAll(where: { $0.id == id })
        groups = normalizedGroups(
            groups.map { group in
                var updatedGroup = group
                updatedGroup.timerIDs.removeAll(where: { $0 == id })
                return updatedGroup
            }
        )
        cleanupFloatingUIState()
        scheduleStateSave()
    }

    func startAll() {
        let ids = timers.map(\.id)
        ids.forEach(start(_:))
    }

    func pauseAll() {
        let ids = timers.map(\.id)
        ids.forEach(pause(_:))
    }

    func resetAll() {
        let ids = timers.map(\.id)
        ids.forEach(reset(_:))
    }

    func restartAll() {
        let ids = timers.map(\.id)
        ids.forEach(restart(_:))
    }

    func startGroup(_ groupID: UUID) {
        timers(inGroup: groupID).map(\.id).forEach(start(_:))
    }

    func pauseGroup(_ groupID: UUID) {
        timers(inGroup: groupID).map(\.id).forEach(pause(_:))
    }

    func resetGroup(_ groupID: UUID) {
        timers(inGroup: groupID).map(\.id).forEach(reset(_:))
    }

    func restartGroup(_ groupID: UUID) {
        timers(inGroup: groupID).map(\.id).forEach(restart(_:))
    }

    func processTick() {
        let now = nowProvider()
        var updatedTimers = timers
        var finishedTimers: [TimerItem] = []
        var hasChanges = false

        for index in updatedTimers.indices {
            guard updatedTimers[index].state == .running, let endDate = updatedTimers[index].endDate else {
                continue
            }

            let remaining = max(endDate.timeIntervalSince(now), 0)
            if abs(updatedTimers[index].remainingDuration - remaining) > 0.01 {
                updatedTimers[index].remainingDuration = remaining
                hasChanges = true
            }

            if remaining <= 0 {
                updatedTimers[index].remainingDuration = 0
                updatedTimers[index].state = .finished
                updatedTimers[index].endDate = nil
                finishedTimers.append(updatedTimers[index])
                hasChanges = true
            }
        }

        if hasChanges {
            timers = updatedTimers
        }

        finishedTimers.forEach(alertManager.notifyTimerFinished(_:))
    }

    private func resolvedTargetMemoIDForAI() -> UUID {
        if let focusedMemoID, memo(for: focusedMemoID) != nil {
            return focusedMemoID
        }

        if let latestMemo = memos.max(by: { ($0.lastFocusedAt ?? $0.createdAt) < ($1.lastFocusedAt ?? $1.createdAt) }) {
            focusedMemoID = latestMemo.id
            return latestMemo.id
        }

        let newMemoID = addMemo()
        focusedMemoID = newMemoID
        return newMemoID
    }

    private func appendConversationEntry(_ entry: MemoConversationEntry, to memoID: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        memos[index].conversationEntries.append(entry)
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    @discardableResult
    private func appendAssistantPlaceholder(to memoID: UUID) -> UUID {
        let entry = MemoConversationEntry(
            id: UUID(),
            role: .assistant,
            createdAt: nowProvider(),
            text: "",
            imageData: nil,
            imageFilename: nil,
            isStreaming: true
        )

        appendConversationEntry(entry, to: memoID)
        return entry.id
    }

    private func requestAssistantResponse(
        memoID: UUID,
        userEntry: MemoConversationEntry,
        requestPrompt: String,
        imageData: Data?,
        imageFilename _: String?,
        mimeType: String?
    ) async {
        guard let memo = memo(for: memoID) else {
            return
        }

        guard memo.assistantStatus == .idle || memo.assistantStatus == .capturing else {
            appendSystemError("이미 이 메모에서 다른 요청이 진행 중입니다.", to: memoID)
            return
        }

        let model = activeAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            appendSystemError("\(aiProvider.label) 모델명이 비어 있습니다.", to: memoID)
            return
        }

        let keyCandidates = availableKeyCandidates(for: aiProvider)

        guard !keyCandidates.isEmpty else {
            appendSystemError("\(aiProvider.label) API 키가 비어 있습니다.", to: memoID)
            return
        }

        appendConversationEntry(userEntry, to: memoID)
        setMemoAssistantStatus(.requesting, for: memoID)

        var attemptedSlots: [Int] = []
        var lastError: Error?

        for candidate in keyCandidates {
            attemptedSlots.append(candidate.slot + 1)
            let assistantEntryID = appendAssistantPlaceholder(to: memoID)

            do {
                try await visionAssistantService.streamResponse(
                    provider: aiProvider,
                    model: model,
                    apiKey: candidate.key,
                    prompt: requestPrompt,
                    imageData: imageData,
                    mimeType: mimeType
                ) { [weak self] delta in
                    Task { @MainActor [weak self] in
                        self?.appendAssistantDelta(delta, entryID: assistantEntryID, memoID: memoID)
                    }
                }

                setSelectedKeySlot(candidate.slot, for: aiProvider)
                await finalizeAssistantResponse(entryID: assistantEntryID, memoID: memoID)
                return
            } catch {
                lastError = error
                removeConversationEntry(entryID: assistantEntryID, from: memoID)

                if Task.isCancelled { return }
                if !shouldFailOverToNextKey(after: error) {
                    break
                }
            }
        }

        guard !Task.isCancelled else { return }
        handleAssistantFailure(failoverError(from: lastError, attemptedSlots: attemptedSlots), memoID: memoID)
    }

    private func appendAssistantDelta(_ delta: String, entryID: UUID, memoID: UUID) {
        guard
            let memoIndex = memos.firstIndex(where: { $0.id == memoID }),
            let entryIndex = memos[memoIndex].conversationEntries.firstIndex(where: { $0.id == entryID })
        else {
            return
        }

        memos[memoIndex].conversationEntries[entryIndex].text += delta
        memos[memoIndex].conversationEntries[entryIndex].isStreaming = true
        memos[memoIndex].updatedAt = nowProvider()

        if memos[memoIndex].assistantStatus != .streaming {
            memos[memoIndex].assistantStatus = .streaming
        }

        scheduleStateSave()
    }

    private func finalizeAssistantResponse(entryID: UUID, memoID: UUID) async {
        guard
            let memoIndex = memos.firstIndex(where: { $0.id == memoID }),
            let entryIndex = memos[memoIndex].conversationEntries.firstIndex(where: { $0.id == entryID })
        else {
            return
        }

        memos[memoIndex].conversationEntries[entryIndex].isStreaming = false
        memos[memoIndex].assistantStatus = .idle
        memos[memoIndex].updatedAt = nowProvider()
        await persistAssistantResponseTranscript(memoIndex: memoIndex, entryIndex: entryIndex)
        scheduleStateSave()
    }

    private func handleAssistantFailure(_ error: Error, memoID: UUID) {
        removeEmptyStreamingAssistantEntry(from: memoID)
        setMemoAssistantStatus(.idle, for: memoID)
        appendSystemError(error.localizedDescription, to: memoID)
    }

    private func removeEmptyStreamingAssistantEntry(from memoID: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        memos[index].conversationEntries.removeAll {
            $0.role == .assistant && $0.isStreaming && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func removeConversationEntry(entryID: UUID, from memoID: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        memos[index].conversationEntries.removeAll(where: { $0.id == entryID })
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    private func appendSystemError(_ message: String, to memoID: UUID) {
        appendConversationEntry(
            MemoConversationEntry(
                id: UUID(),
                role: .systemError,
                createdAt: nowProvider(),
                text: message,
                imageData: nil,
                imageFilename: nil,
                isStreaming: false
            ),
            to: memoID
        )
    }

    private func setMemoAssistantStatus(_ status: MemoAssistantStatus, for memoID: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        memos[index].assistantStatus = status
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    private func persistAssistantResponseTranscript(memoIndex: Int, entryIndex: Int) async {
        guard memos.indices.contains(memoIndex), memos[memoIndex].conversationEntries.indices.contains(entryIndex) else {
            return
        }

        let memo = memos[memoIndex]
        let entry = memo.conversationEntries[entryIndex]

        guard entry.role == .assistant else {
            return
        }

        do {
            try await memoTranscriptStore.appendAssistantResponse(memo: memo, responseText: entry.text, at: entry.createdAt)
        } catch {
            persistenceStatusMessage = "답변 txt 저장 실패: \(error.localizedDescription)"
        }
    }

    private func recordCapturedImage(_ imageData: Data, for memoID: UUID) {
        guard let index = memos.firstIndex(where: { $0.id == memoID }) else {
            return
        }

        memos[index].lastCapturedImageData = imageData
        memos[index].updatedAt = nowProvider()
        scheduleStateSave()
    }

    private func performTextOnlyAISmokeTest() async {
        let memoID = resolvedTargetMemoIDForAI()
        aiSmokeStatus = "텍스트-only 테스트 실행 중..."
        await sendTextPrompt(
            "연결 테스트입니다. 성공하면 '텍스트 테스트 성공' 한 줄만 답해주세요.",
            to: memoID
        )
        aiSmokeStatus = smokeStatusSummary(prefix: "텍스트-only", memoID: memoID)
    }

    private func performCaptureOnlySmokeTest() async {
        let memoID = resolvedTargetMemoIDForAI()
        revealMemo(memoID)
        aiSmokeStatus = "화면 캡처-only 테스트 실행 중..."

        do {
            let screenshot = try await screenCaptureService.captureCurrentScreenJPEG()
            setMemoImage(memoID, imageData: screenshot.data, imageFilename: screenshot.filename)
            recordCapturedImage(screenshot.data, for: memoID)
            let kilobytes = max(screenshot.data.count / 1024, 1)
            aiSmokeStatus = "화면 캡처-only 성공: \(screenshot.filename) · \(kilobytes)KB"
        } catch {
            appendSystemError(error.localizedDescription, to: memoID)
            aiSmokeStatus = "화면 캡처-only 실패: \(error.localizedDescription)"
        }
    }

    private func performCaptureAISmokeTest() async {
        let memoID = resolvedTargetMemoIDForAI()
        revealMemo(memoID)
        aiSmokeStatus = "화면 캡처+AI 테스트 실행 중..."

        guard memo(for: memoID)?.assistantStatus == .idle else {
            let message = "이미 이 메모에서 다른 요청이 진행 중입니다."
            appendSystemError(message, to: memoID)
            aiSmokeStatus = "화면 캡처+AI 실패: \(message)"
            return
        }

        do {
            let screenshot = try await screenCaptureService.captureCurrentScreenJPEG()
            recordCapturedImage(screenshot.data, for: memoID)

            let prompt = "연결 테스트입니다. 이 이미지를 읽을 수 있으면 '이미지 테스트 성공' 한 줄만 답하고, 읽을 수 없으면 이유를 한 줄로 답해주세요."

            await requestAssistantResponse(
                memoID: memoID,
                userEntry: MemoConversationEntry(
                    id: UUID(),
                    role: .userCapture,
                    createdAt: nowProvider(),
                    text: prompt,
                    imageData: screenshot.data,
                    imageFilename: screenshot.filename,
                    isStreaming: false
                ),
                requestPrompt: prompt,
                imageData: screenshot.data,
                imageFilename: screenshot.filename,
                mimeType: screenshot.mimeType
            )

            aiSmokeStatus = smokeStatusSummary(prefix: "화면 캡처+AI", memoID: memoID)
        } catch {
            appendSystemError(error.localizedDescription, to: memoID)
            aiSmokeStatus = "화면 캡처+AI 실패: \(error.localizedDescription)"
        }
    }

    private func smokeStatusSummary(prefix: String, memoID: UUID) -> String {
        guard let memo = memo(for: memoID), let entry = memo.latestResponseEntry else {
            return "\(prefix) 테스트 완료: 메모에서 결과를 확인하세요."
        }

        let preview = entry.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !preview.isEmpty else {
            return "\(prefix) 테스트 완료: 응답은 비어 있습니다."
        }

        let clipped = String(preview.prefix(88))
        switch entry.role {
        case .assistant:
            return "\(prefix) 성공: \(clipped)"
        case .systemError:
            return "\(prefix) 실패: \(clipped)"
        default:
            return "\(prefix) 완료: \(clipped)"
        }
    }

    func handleApplicationDidResignActive() {
        persistStateNow()
    }

    func handleApplicationWillTerminate() {
        persistStateNow()
    }

    func flushPersistedStateNow() {
        persistStateNow()
    }

    private func restorePersistedAppStateIfAvailable() {
        do {
            guard let snapshot = try appStateStore.load() else {
                persistenceStatusMessage = "저장 상태 없음"
                return
            }

            applyPersistedState(snapshot)
            hasLoadedPersistedState = true
            persistenceStatusMessage = "저장 상태 복구됨"
        } catch {
            persistenceStatusMessage = "저장 상태를 읽지 못해 새로 시작합니다."
            try? appStateStore.clear()
        }
    }

    private func applyPersistedState(_ snapshot: AppStateSnapshot) {
        isRestoringPersistedState = true
        defer { isRestoringPersistedState = false }

        let now = nowProvider()
        timers = restoredTimers(from: snapshot.timers, now: now)
        groups = snapshot.groups
        memos = snapshot.memos.map { $0.restored(now: now) }
        floatingOpacity = Self.clampedOpacity(snapshot.floatingOpacity)
        areFloatingHUDsVisible = snapshot.areFloatingHUDsVisible
        controlPanelMode = snapshot.controlPanelMode
        minimizedTimerIDs = Set(snapshot.minimizedTimerIDs)
        minimizedGroupIDs = Set(snapshot.minimizedGroupIDs)
        minimizedMemoIDs = Set(snapshot.minimizedMemoIDs)
        focusedMemoID = snapshot.focusedMemoID
        aiProvider = snapshot.aiConfiguration.provider
        openAIModel = Self.normalizedModel(provider: .openAI, model: snapshot.aiConfiguration.openAIModel)
        geminiModel = Self.normalizedModel(provider: .gemini, model: snapshot.aiConfiguration.geminiModel)
        selectedOpenAIKeySlot = Self.clampedKeySlot(snapshot.aiConfiguration.selectedOpenAIKeySlot)
        selectedGeminiKeySlot = Self.clampedKeySlot(snapshot.aiConfiguration.selectedGeminiKeySlot)
        timerPanelOrigins = Dictionary(uniqueKeysWithValues: snapshot.panelOrigins.timerOrigins.map { ($0.id, $0.origin.cgPoint) })
        groupPanelOrigins = Dictionary(uniqueKeysWithValues: snapshot.panelOrigins.groupOrigins.map { ($0.id, $0.origin.cgPoint) })
        memoPanelOrigins = Dictionary(uniqueKeysWithValues: snapshot.panelOrigins.memoOrigins.map { ($0.id, $0.origin.cgPoint) })
        controlPanelOrigin = snapshot.panelOrigins.controlPanelOrigin?.cgPoint

        groups = normalizedGroups(groups)
        cleanupFloatingUIState()
        nextTimerNumber = max(timers.count + 1, 1)
        nextGroupNumber = max(groups.count + 1, 1)
        persistAISettings()
    }

    private func restoredTimers(from persistedTimers: [TimerItem], now: Date) -> [TimerItem] {
        persistedTimers.map { timer in
            var restoredTimer = timer

            switch restoredTimer.state {
            case .running:
                if let endDate = restoredTimer.endDate {
                    let remaining = max(endDate.timeIntervalSince(now), 0)
                    restoredTimer.remainingDuration = remaining
                    if remaining <= 0 {
                        restoredTimer.remainingDuration = 0
                        restoredTimer.state = .finished
                        restoredTimer.endDate = nil
                    }
                } else {
                    restoredTimer.state = restoredTimer.remainingDuration > 0 ? .paused : .finished
                }
            case .idle, .paused:
                restoredTimer.endDate = nil
                if restoredTimer.remainingDuration <= 0 {
                    restoredTimer.remainingDuration = 0
                    restoredTimer.state = .finished
                }
            case .finished:
                restoredTimer.remainingDuration = 0
                restoredTimer.endDate = nil
            }

            return restoredTimer
        }
    }

    private func scheduleStateSave() {
        guard !isRestoringPersistedState else {
            return
        }

        pendingStateSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistStateNow()
            }
        }
        pendingStateSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func persistStateNow() {
        guard !isRestoringPersistedState else {
            return
        }

        pendingStateSaveWorkItem?.cancel()
        pendingStateSaveWorkItem = nil

        do {
            try appStateStore.save(stateSnapshot())
            if persistenceStatusMessage == "저장 상태 없음" {
                persistenceStatusMessage = "자동 저장 켜짐"
            }
        } catch {
            persistenceStatusMessage = "상태 저장 실패: \(error.localizedDescription)"
        }
    }

    private func stateSnapshot() -> AppStateSnapshot {
        AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            timers: timers,
            groups: groups,
            memos: memos.map(MemoItemSnapshot.init),
            floatingOpacity: floatingOpacity,
            areFloatingHUDsVisible: areFloatingHUDsVisible,
            controlPanelMode: controlPanelMode,
            minimizedTimerIDs: Array(minimizedTimerIDs),
            minimizedGroupIDs: Array(minimizedGroupIDs),
            minimizedMemoIDs: Array(minimizedMemoIDs),
            focusedMemoID: focusedMemoID,
            aiConfiguration: AIConfigurationStateSnapshot(
                provider: aiProvider,
                openAIModel: openAIModel,
                geminiModel: geminiModel,
                selectedOpenAIKeySlot: selectedOpenAIKeySlot,
                selectedGeminiKeySlot: selectedGeminiKeySlot
            ),
            panelOrigins: FloatingPanelOriginsSnapshot(
                timerOrigins: timerPanelOrigins.map { FloatingPanelOriginSnapshot(id: $0.key, origin: CGPointSnapshot($0.value)) },
                groupOrigins: groupPanelOrigins.map { FloatingPanelOriginSnapshot(id: $0.key, origin: CGPointSnapshot($0.value)) },
                memoOrigins: memoPanelOrigins.map { FloatingPanelOriginSnapshot(id: $0.key, origin: CGPointSnapshot($0.value)) },
                controlPanelOrigin: controlPanelOrigin.map(CGPointSnapshot.init)
            )
        )
    }

    private func persistAISettings() {
        settingsStore.save(
            AISettingsSnapshot(
                provider: aiProvider,
                openAIModel: openAIModel,
                geminiModel: geminiModel,
                openAIAPIKeys: openAIAPIKeys,
                geminiAPIKeys: geminiAPIKeys,
                selectedOpenAIKeySlot: selectedOpenAIKeySlot,
                selectedGeminiKeySlot: selectedGeminiKeySlot
            )
        )
    }

    private func currentSelectedKeySlot(for provider: AIProvider) -> Int {
        switch provider {
        case .openAI:
            return selectedOpenAIKeySlot
        case .gemini:
            return selectedGeminiKeySlot
        }
    }

    private func preferredDisplayKeySlot(for provider: AIProvider) -> Int? {
        let selectedSlot = currentSelectedKeySlot(for: provider)
        let selectedKey: String

        switch provider {
        case .openAI:
            selectedKey = Self.key(at: selectedSlot, in: openAIAPIKeys)
        case .gemini:
            selectedKey = Self.key(at: selectedSlot, in: geminiAPIKeys)
        }

        if !selectedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedSlot
        }

        return availableKeyCandidates(for: provider).first?.slot
    }

    private func availableKeyCandidates(for provider: AIProvider) -> [(slot: Int, key: String)] {
        let keys: [String]
        switch provider {
        case .openAI:
            keys = openAIAPIKeys
        case .gemini:
            keys = geminiAPIKeys
        }

        return AISettingsSnapshot.normalizedKeys(keys)
            .enumerated()
            .compactMap { index, key in
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedKey.isEmpty else {
                    return nil
                }

                return (slot: index, key: trimmedKey)
            }
    }

    private func setSelectedKeySlot(_ slot: Int, for provider: AIProvider) {
        let normalizedSlot = Self.clampedKeySlot(slot)

        switch provider {
        case .openAI:
            guard selectedOpenAIKeySlot != normalizedSlot else {
                return
            }

            selectedOpenAIKeySlot = normalizedSlot
        case .gemini:
            guard selectedGeminiKeySlot != normalizedSlot else {
                return
            }

            selectedGeminiKeySlot = normalizedSlot
        }

        persistAISettings()
        scheduleStateSave()
    }

    private func shouldFailOverToNextKey(after error: Error) -> Bool {
        if let visionError = error as? VisionAssistantError {
            switch visionError {
            case .missingAPIKey, .missingModel:
                return false
            case let .httpError(code, message):
                if [401, 403, 429].contains(code) || code >= 500 {
                    return true
                }

                let normalizedMessage = message.lowercased()
                if normalizedMessage.contains("api 키가 유효하지") || normalizedMessage.contains("api key not valid") || normalizedMessage.contains("api_key_invalid") || normalizedMessage.contains("quota") || normalizedMessage.contains("rate limit") {
                    return true
                }

                return false
            case let .serviceError(message):
                let normalizedMessage = message.lowercased()
                return normalizedMessage.contains("api key") || normalizedMessage.contains("quota") || normalizedMessage.contains("rate limit")
            case .emptyResponse:
                return false
            case .cancelled:
                return false
            }
        }

        return false
    }

    private func failoverError(from error: Error?, attemptedSlots: [Int]) -> Error {
        guard let error else {
            return VisionAssistantError.serviceError("AI 요청에 실패했습니다.")
        }

        guard attemptedSlots.count > 1 else {
            return error
        }

        let slotSummary = attemptedSlots.map(String.init).joined(separator: ", ")
        return VisionAssistantError.serviceError(
            "\(aiProvider.label) 키 슬롯 \(slotSummary) 순서로 시도했지만 모두 실패했습니다. 마지막 오류: \(error.localizedDescription)"
        )
    }

    private func resolvedPrompt(for memoID: UUID) -> String {
        memo(for: memoID)?.activePromptText ?? "이 화면에서 중요한 내용, 문제점, 다음 액션을 한국어로 간단히 정리해줘."
    }

    private func composedPrompt(for memoID: UUID, userText: String) -> String {
        let basePrompt = resolvedPrompt(for: memoID).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUserText.isEmpty else {
            return basePrompt
        }

        if basePrompt.isEmpty {
            return trimmedUserText
        }

        return """
        \(basePrompt)

        사용자 질문:
        \(trimmedUserText)
        """
    }

    private func startTicker() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.processTick()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func updateTimer(_ id: UUID, mutate: (inout TimerItem, Date) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let now = nowProvider()
        var updatedTimers = timers
        mutate(&updatedTimers[index], now)
        timers = updatedTimers
        scheduleStateSave()
    }

    private func normalizedGroups(_ groups: [TimerGroup]) -> [TimerGroup] {
        let validTimerIDs = Set(timers.map(\.id))

        return groups.compactMap { group in
            var seen: Set<UUID> = []
            let filteredIDs = group.timerIDs.filter { timerID in
                guard validTimerIDs.contains(timerID) else {
                    return false
                }

                return seen.insert(timerID).inserted
            }

            guard filteredIDs.count > 1 else {
                return nil
            }

            var updatedGroup = group
            updatedGroup.timerIDs = filteredIDs
            return updatedGroup
        }
    }

    private func cleanupFloatingUIState() {
        let validTimerIDs = Set(activeFloatingTimerIDs)
        let validGroupIDs = Set(activeFloatingGroupIDs)
        let validMemoIDs = Set(activeFloatingMemoIDs)

        minimizedTimerIDs = minimizedTimerIDs.intersection(validTimerIDs)
        minimizedGroupIDs = minimizedGroupIDs.intersection(validGroupIDs)
        minimizedMemoIDs = minimizedMemoIDs.intersection(validMemoIDs)
        timerPanelOrigins = timerPanelOrigins.filter { validTimerIDs.contains($0.key) }
        groupPanelOrigins = groupPanelOrigins.filter { validGroupIDs.contains($0.key) }
        memoPanelOrigins = memoPanelOrigins.filter { validMemoIDs.contains($0.key) }
        if let focusedMemoID, !validMemoIDs.contains(focusedMemoID) {
            self.focusedMemoID = nil
        }
    }

    private static func normalizedSettings(_ snapshot: AISettingsSnapshot) -> AISettingsSnapshot {
        var normalized = snapshot
        normalized.openAIModel = normalizedModel(provider: .openAI, model: normalized.openAIModel)
        normalized.geminiModel = normalizedModel(provider: .gemini, model: normalized.geminiModel)
        normalized.openAIAPIKeys = AISettingsSnapshot.normalizedKeys(normalized.openAIAPIKeys)
        normalized.geminiAPIKeys = AISettingsSnapshot.normalizedKeys(normalized.geminiAPIKeys)
        normalized.selectedOpenAIKeySlot = clampedKeySlot(normalized.selectedOpenAIKeySlot)
        normalized.selectedGeminiKeySlot = clampedKeySlot(normalized.selectedGeminiKeySlot)
        return normalized
    }

    private static func normalizedModel(provider: AIProvider, model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider == .gemini else {
            return trimmed
        }

        switch trimmed.lowercased() {
        case "gemini-3.0-flash-preview":
            return "gemini-3-flash-preview"
        default:
            return trimmed
        }
    }

    private static func clampedOpacity(_ opacity: Double) -> Double {
        min(max(opacity, 0.2), 1.0)
    }

    private static func clampedKeySlot(_ slot: Int) -> Int {
        AISettingsSnapshot.clampedSlot(slot)
    }

    private static func key(at slot: Int, in keys: [String]) -> String {
        let normalizedKeys = AISettingsSnapshot.normalizedKeys(keys)
        return normalizedKeys[clampedKeySlot(slot)]
    }

    private static func filledKeySlots(in keys: [String]) -> Set<Int> {
        Set(
            AISettingsSnapshot.normalizedKeys(keys)
                .enumerated()
                .compactMap { index, key in
                    key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : index
                }
        )
    }
}
