import Foundation
import Security

enum FinnhubCredentialStore {
    private static let defaultService = "org.senatov.mimitrends.apple.finnhub"
    private static let account = "api-key"

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
            kSecAttrAccount as String: account
        ]
    }

    #if os(macOS)
    private static func preferenceKey(_ service: String) -> String { "credential.finnhub.\(service)" }

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
