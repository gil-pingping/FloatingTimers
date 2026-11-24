import Foundation
import os
import Security

protocol KeychainStoring {
    func string(for account: String) -> String?
    /// 빈 문자열이면 항목을 삭제한다. 성공 여부를 반환한다.
    @discardableResult
    func set(_ value: String, for account: String) -> Bool
}

struct AISettingsSnapshot: Equatable {
    static let maxKeySlots = 10

    var provider: AIProvider
    var openAIModel: String
    var geminiModel: String
    var openAIAPIKeys: [String]
    var geminiAPIKeys: [String]
    var selectedOpenAIKeySlot: Int
    var selectedGeminiKeySlot: Int

    init(
        provider: AIProvider,
        openAIModel: String,
        geminiModel: String,
        openAIAPIKey: String = "",
        geminiAPIKey: String = "",
        openAIAPIKeys: [String]? = nil,
        geminiAPIKeys: [String]? = nil,
        selectedOpenAIKeySlot: Int = 0,
        selectedGeminiKeySlot: Int = 0
    ) {
        self.provider = provider
        self.openAIModel = openAIModel
        self.geminiModel = geminiModel
        self.openAIAPIKeys = Self.normalizedKeys(openAIAPIKeys ?? [openAIAPIKey])
        self.geminiAPIKeys = Self.normalizedKeys(geminiAPIKeys ?? [geminiAPIKey])
        self.selectedOpenAIKeySlot = Self.clampedSlot(selectedOpenAIKeySlot)
        self.selectedGeminiKeySlot = Self.clampedSlot(selectedGeminiKeySlot)
    }

    var openAIAPIKey: String {
        Self.key(at: selectedOpenAIKeySlot, in: openAIAPIKeys)
    }

    var geminiAPIKey: String {
        Self.key(at: selectedGeminiKeySlot, in: geminiAPIKeys)
    }

    static func normalizedKeys(_ keys: [String]) -> [String] {
        let trimmed = Array(keys.prefix(maxKeySlots))
        if trimmed.count == maxKeySlots {
            return trimmed
        }

        return trimmed + Array(repeating: "", count: maxKeySlots - trimmed.count)
    }

    static func clampedSlot(_ slot: Int) -> Int {
        min(max(slot, 0), maxKeySlots - 1)
    }

    private static func key(at slot: Int, in keys: [String]) -> String {
        let normalized = normalizedKeys(keys)
        return normalized[clampedSlot(slot)]
    }

    static let `default` = AISettingsSnapshot(
        provider: .openAI,
        openAIModel: AIProvider.openAI.defaultModel,
        geminiModel: AIProvider.gemini.defaultModel,
        openAIAPIKey: ProcessInfo.processInfo.environment[AIProvider.openAI.envKey] ?? "",
        geminiAPIKey: ProcessInfo.processInfo.environment[AIProvider.gemini.envKey] ?? ""
    )
}

protocol AISettingsPersisting {
    func load() -> AISettingsSnapshot
    func save(_ snapshot: AISettingsSnapshot)
}

final class InMemoryAISettingsStore: AISettingsPersisting {
    private var snapshot: AISettingsSnapshot

    init(snapshot: AISettingsSnapshot = .default) {
        self.snapshot = snapshot
    }

    func load() -> AISettingsSnapshot {
        snapshot
    }

    func save(_ snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }
}

final class PersistentAISettingsStore: AISettingsPersisting {
    private enum DefaultsKey {
        static let provider = "ai.provider"
        static let openAIModel = "ai.openai.model"
        static let geminiModel = "ai.gemini.model"
        /// 레거시: 이전 버전이 API 키를 평문으로 저장하던 위치. 마이그레이션 후 삭제한다.
        static let legacyOpenAIKeys = "ai.openai.keys"
        static let legacyGeminiKeys = "ai.gemini.keys"
        static let openAISelectedKeySlot = "ai.openai.keyslot"
        static let geminiSelectedKeySlot = "ai.gemini.keyslot"
    }

    private enum KeychainKey {
        static let openAILegacy = "ai.openai.key"
        static let geminiLegacy = "ai.gemini.key"

        static func openAI(slot: Int) -> String {
            "ai.openai.key.\(slot)"
        }

        static func gemini(slot: Int) -> String {
            "ai.gemini.key.\(slot)"
        }
    }

    private let userDefaults: UserDefaults
    private let keychain: any KeychainStoring

    init(
        userDefaults: UserDefaults = .standard,
        keychain: any KeychainStoring = KeychainStore(service: "com.giyun.floatingtimers.ai")
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
    }

    func load() -> AISettingsSnapshot {
        var snapshot = AISettingsSnapshot.default

        if
            let rawValue = userDefaults.string(forKey: DefaultsKey.provider),
            let provider = AIProvider(rawValue: rawValue)
        {
            snapshot.provider = provider
        }

        if let openAIModel = userDefaults.string(forKey: DefaultsKey.openAIModel), !openAIModel.isEmpty {
            snapshot.openAIModel = openAIModel
        }

        if let geminiModel = userDefaults.string(forKey: DefaultsKey.geminiModel), !geminiModel.isEmpty {
            snapshot.geminiModel = geminiModel
        }

        snapshot.selectedOpenAIKeySlot = AISettingsSnapshot.clampedSlot(
            userDefaults.object(forKey: DefaultsKey.openAISelectedKeySlot) as? Int ?? snapshot.selectedOpenAIKeySlot
        )
        snapshot.selectedGeminiKeySlot = AISettingsSnapshot.clampedSlot(
            userDefaults.object(forKey: DefaultsKey.geminiSelectedKeySlot) as? Int ?? snapshot.selectedGeminiKeySlot
        )

        snapshot.openAIAPIKeys = loadKeys(
            accountProvider: KeychainKey.openAI(slot:),
            legacyAccount: KeychainKey.openAILegacy,
            legacyDefaultsKey: DefaultsKey.legacyOpenAIKeys,
            fallback: snapshot.openAIAPIKeys
        )
        snapshot.geminiAPIKeys = loadKeys(
            accountProvider: KeychainKey.gemini(slot:),
            legacyAccount: KeychainKey.geminiLegacy,
            legacyDefaultsKey: DefaultsKey.legacyGeminiKeys,
            fallback: snapshot.geminiAPIKeys
        )

        return snapshot
    }

    func save(_ snapshot: AISettingsSnapshot) {
        // 키가 아닌 설정만 UserDefaults에 저장한다. API 키는 Keychain에만 둔다.
        userDefaults.set(snapshot.provider.rawValue, forKey: DefaultsKey.provider)
        userDefaults.set(snapshot.openAIModel, forKey: DefaultsKey.openAIModel)
        userDefaults.set(snapshot.geminiModel, forKey: DefaultsKey.geminiModel)
        userDefaults.set(snapshot.selectedOpenAIKeySlot, forKey: DefaultsKey.openAISelectedKeySlot)
        userDefaults.set(snapshot.selectedGeminiKeySlot, forKey: DefaultsKey.geminiSelectedKeySlot)

        let openAISaved = saveToKeychain(
            AISettingsSnapshot.normalizedKeys(snapshot.openAIAPIKeys),
            accountProvider: KeychainKey.openAI(slot:)
        )
        let geminiSaved = saveToKeychain(
            AISettingsSnapshot.normalizedKeys(snapshot.geminiAPIKeys),
            accountProvider: KeychainKey.gemini(slot:)
        )

        // Keychain 저장이 성공한 경우에만 레거시 평문 사본을 지운다 (키 유실 방지).
        if openAISaved { userDefaults.removeObject(forKey: DefaultsKey.legacyOpenAIKeys) }
        if geminiSaved { userDefaults.removeObject(forKey: DefaultsKey.legacyGeminiKeys) }
    }

    /// Keychain 슬롯 → (없으면) 레거시 UserDefaults 평문 → 레거시 단일 Keychain 항목 → fallback(환경변수) 순으로 읽는다.
    /// 레거시 위치에서 찾은 키는 Keychain 슬롯으로 옮기고 원본을 삭제한다.
    private func loadKeys(
        accountProvider: (Int) -> String,
        legacyAccount: String,
        legacyDefaultsKey: String,
        fallback: [String]
    ) -> [String] {
        let keychainKeys = (0 ..< AISettingsSnapshot.maxKeySlots).map { slot in
            keychain.string(for: accountProvider(slot)) ?? ""
        }
        for (slot, value) in keychainKeys.enumerated() {
            lastWrittenKeychainValues[accountProvider(slot)] = value
        }

        if let legacyDefaultsKeys = userDefaults.stringArray(forKey: legacyDefaultsKey) {
            let legacyKeys = AISettingsSnapshot.normalizedKeys(legacyDefaultsKeys)
            // 슬롯별로 Keychain 값을 우선하고, 비어 있는 슬롯만 레거시 값으로 채운다.
            let merged = zip(keychainKeys, legacyKeys).map { $0.isEmpty ? $1 : $0 }
            if saveToKeychain(merged, accountProvider: accountProvider) {
                userDefaults.removeObject(forKey: legacyDefaultsKey)
            }
            if !merged.allSatisfy(\.isEmpty) {
                return merged
            }
        } else if !keychainKeys.allSatisfy(\.isEmpty) {
            return keychainKeys
        }

        if let legacyValue = keychain.string(for: legacyAccount), !legacyValue.isEmpty {
            var migrated = Array(repeating: "", count: AISettingsSnapshot.maxKeySlots)
            migrated[0] = legacyValue
            if keychain.set(legacyValue, for: accountProvider(0)) {
                keychain.set("", for: legacyAccount)
            }
            return migrated
        }

        return AISettingsSnapshot.normalizedKeys(fallback)
    }

    /// 마지막으로 기록한 값과 다른 슬롯만 쓴다. 입력 필드가 키 입력마다 save()를 호출하므로 불필요한 Keychain 쓰기를 줄인다.
    private var lastWrittenKeychainValues: [String: String] = [:]

    @discardableResult
    private func saveToKeychain(_ keys: [String], accountProvider: (Int) -> String) -> Bool {
        var allSucceeded = true
        for (slot, value) in AISettingsSnapshot.normalizedKeys(keys).enumerated() {
            let account = accountProvider(slot)
            if lastWrittenKeychainValues[account] == value {
                continue
            }
            if keychain.set(value, for: account) {
                lastWrittenKeychainValues[account] = value
            } else {
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}

final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func string(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                os_log(.error, "KeychainStore: SecItemCopyMatching 실패 (account: %{public}@, status: %d)", account, status)
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return delete(account: account)
        }

        let data = Data(value.utf8)
        let query = baseQuery(for: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            os_log(.error, "KeychainStore: SecItemUpdate 실패 (account: %{public}@, status: %d)", account, updateStatus)
            return false
        }

        var newQuery = query
        newQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            os_log(.error, "KeychainStore: SecItemAdd 실패 (account: %{public}@, status: %d)", account, addStatus)
            return false
        }
        return true
    }

    private func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            os_log(.error, "KeychainStore: SecItemDelete 실패 (account: %{public}@, status: %d)", account, status)
            return false
        }
        return true
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
