import Foundation
import Security

enum FinnhubCredentialStore {
    private static let defaultService = "org.senatov.mimitrends.apple.finnhub"
    private enum Account {
        static let apiKey = "api-key"
        static let webhookSecret = "webhook-secret"
    }

    static func load(service: String = defaultService) throws -> String? {
        #if os(macOS)
        return loadMacPreference(service: service)
        #else
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.unavailable(status)
        }
        return key
        #endif
    }

    static func save(_ key: String, service: String = defaultService) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw CredentialStoreError.emptyKey }
        #if os(macOS)
        UserDefaults.standard.set(normalized, forKey: preferenceKey(service))
        #else
        let data = Data(normalized.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(service: service) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.unavailable(status) }

        var addition = baseQuery(service: service)
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unavailable(addStatus)
        }
        #endif
    }

    static func delete(service: String = defaultService) throws {
        #if os(macOS)
        UserDefaults.standard.removeObject(forKey: preferenceKey(service))
        #else
        let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unavailable(status)
        }
        #endif
    }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Account.apiKey
        ]
    }

    static func loadWebhookSecret() throws -> String? {
        try loadCredential(account: Account.webhookSecret)
    }

    static func saveWebhookSecret(_ secret: String) throws {
        try saveCredential(secret, account: Account.webhookSecret)
    }

    static func deleteWebhookSecret() throws {
        try deleteCredential(account: Account.webhookSecret)
    }

    private static func loadCredential(account: String, service: String = defaultService) throws -> String? {
        #if os(macOS)
        return UserDefaults.standard.string(forKey: preferenceKey(service, account: account))
        #else
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.unavailable(status)
        }
        return value
        #endif
    }

    private static func saveCredential(_ value: String, account: String, service: String = defaultService) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw CredentialStoreError.emptyKey }
        #if os(macOS)
        UserDefaults.standard.set(normalized, forKey: preferenceKey(service, account: account))
        #else
        let data = Data(normalized.utf8)
        let query = baseQuery(service: service, account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.unavailable(status) }
        var addition = query
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialStoreError.unavailable(addStatus) }
        #endif
    }

    private static func deleteCredential(account: String, service: String = defaultService) throws {
        #if os(macOS)
        UserDefaults.standard.removeObject(forKey: preferenceKey(service, account: account))
        #else
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unavailable(status)
        }
        #endif
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    #if os(macOS)
    private static func preferenceKey(_ service: String, account: String = Account.apiKey) -> String {
        account == Account.apiKey
            ? "credential.finnhub.\(service)"
            : "credential.finnhub.\(service).\(account)"
    }

    private static func loadMacPreference(service: String) -> String? {
        UserDefaults.standard.string(forKey: preferenceKey(service))
    }
    #endif
}

enum CredentialStoreError: LocalizedError {
    case emptyKey
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey: "Enter a Finnhub API key."
        case .unavailable: "Keychain is unavailable. Try again after unlocking this device."
        }
    }
}
