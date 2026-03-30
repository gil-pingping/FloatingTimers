import Foundation
import os
import Security

protocol KeychainStoring {
    func string(for account: String) -> String?
    func strings() -> [String: String]
    func set(_ value: String, for account: String)
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
        static let openAIKeys = "ai.openai.keys"
        static let geminiKeys = "ai.gemini.keys"
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
        var migratedKeysFromKeychain = false

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

        snapshot.openAIAPIKeys = loadKeysFromDefaults(defaultsKey: DefaultsKey.openAIKeys)
        snapshot.geminiAPIKeys = loadKeysFromDefaults(defaultsKey: DefaultsKey.geminiKeys)

        if snapshot.openAIAPIKeys.allSatisfy(\.isEmpty) || snapshot.geminiAPIKeys.allSatisfy(\.isEmpty) {
            let keychainValues = keychain.strings()

            if snapshot.openAIAPIKeys.allSatisfy(\.isEmpty) {
                snapshot.openAIAPIKeys = loadKeysFromKeychain(
                    legacyAccount: KeychainKey.openAILegacy,
                    accountProvider: KeychainKey.openAI(slot:),
                    keychainValues: keychainValues
                )
                migratedKeysFromKeychain = migratedKeysFromKeychain || !snapshot.openAIAPIKeys.allSatisfy(\.isEmpty)
            }

            if snapshot.geminiAPIKeys.allSatisfy(\.isEmpty) {
                snapshot.geminiAPIKeys = loadKeysFromKeychain(
                    legacyAccount: KeychainKey.geminiLegacy,
                    accountProvider: KeychainKey.gemini(slot:),
                    keychainValues: keychainValues
                )
                migratedKeysFromKeychain = migratedKeysFromKeychain || !snapshot.geminiAPIKeys.allSatisfy(\.isEmpty)
            }
        }

        if migratedKeysFromKeychain {
            userDefaults.set(snapshot.openAIAPIKeys, forKey: DefaultsKey.openAIKeys)
            userDefaults.set(snapshot.geminiAPIKeys, forKey: DefaultsKey.geminiKeys)
            userDefaults.synchronize()
        }

        return snapshot
    }

    func save(_ snapshot: AISettingsSnapshot) {
        let normalizedOpenAIKeys = AISettingsSnapshot.normalizedKeys(snapshot.openAIAPIKeys)
        let normalizedGeminiKeys = AISettingsSnapshot.normalizedKeys(snapshot.geminiAPIKeys)

        userDefaults.set(snapshot.provider.rawValue, forKey: DefaultsKey.provider)
        userDefaults.set(snapshot.openAIModel, forKey: DefaultsKey.openAIModel)
        userDefaults.set(snapshot.geminiModel, forKey: DefaultsKey.geminiModel)
        userDefaults.set(normalizedOpenAIKeys, forKey: DefaultsKey.openAIKeys)
        userDefaults.set(normalizedGeminiKeys, forKey: DefaultsKey.geminiKeys)
        userDefaults.set(snapshot.selectedOpenAIKeySlot, forKey: DefaultsKey.openAISelectedKeySlot)
        userDefaults.set(snapshot.selectedGeminiKeySlot, forKey: DefaultsKey.geminiSelectedKeySlot)
        userDefaults.synchronize()
        save(keys: normalizedOpenAIKeys, accountProvider: KeychainKey.openAI(slot:))
        save(keys: normalizedGeminiKeys, accountProvider: KeychainKey.gemini(slot:))
    }

    private func loadKeysFromDefaults(defaultsKey: String) -> [String] {
        AISettingsSnapshot.normalizedKeys(userDefaults.stringArray(forKey: defaultsKey) ?? [])
    }

    private func loadKeysFromKeychain(
        legacyAccount: String,
        accountProvider: (Int) -> String,
        keychainValues: [String: String]
    ) -> [String] {
        var keys = Array(repeating: "", count: AISettingsSnapshot.maxKeySlots)

        for slot in 0 ..< AISettingsSnapshot.maxKeySlots {
            if let value = keychainValues[accountProvider(slot)], !value.isEmpty {
                keys[slot] = value
            }
        }

        if keys.allSatisfy(\.isEmpty), let legacyValue = keychainValues[legacyAccount], !legacyValue.isEmpty {
            keys[0] = legacyValue
        }

        return AISettingsSnapshot.normalizedKeys(keys)
    }

    private func save(
        keys: [String],
        accountProvider: (Int) -> String
    ) {
        let normalizedKeys = AISettingsSnapshot.normalizedKeys(keys)
        for slot in 0 ..< AISettingsSnapshot.maxKeySlots {
            keychain.set(normalizedKeys[slot], for: accountProvider(slot))
        }
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

    func strings() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecReturnAttributes as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return [:]
        }

        let items = (result as? [[String: Any]]) ?? []
        var values: [String: String] = [:]

        for item in items {
            guard
                let account = item[kSecAttrAccount as String] as? String,
                let data = item[kSecValueData as String] as? Data,
                let value = String(data: data, encoding: .utf8)
            else {
                continue
            }

            values[account] = value
        }

        return values
    }

    func set(_ value: String, for account: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delete(account: account)
            return
        }

        let data = Data(value.utf8)
        let query = baseQuery(for: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
            if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
                os_log(.error, "KeychainStore: SecItemAdd 실패 (account: %{public}@, status: %d)", account, addStatus)
            }
        } else if updateStatus != errSecSuccess {
            os_log(.error, "KeychainStore: SecItemUpdate 실패 (account: %{public}@, status: %d)", account, updateStatus)
        }
    }

    private func delete(account: String) {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            os_log(.error, "KeychainStore: SecItemDelete 실패 (account: %{public}@, status: %d)", account, status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
