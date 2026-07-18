import Foundation
import Security

/// Keychain-backed storage for enrichment API keys, so the user pastes their
/// Apollo key once and it never lands in UserDefaults, a file, or a log.
/// Works identically on macOS and iOS (generic-password items).
enum EnrichmentKeyStore {
    private static let service = "com.bryansnotes.highrise.enrichment"

    static func key(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setKey(_ key: String, for account: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteKey(for: account) }
        let data = Data(trimmed.utf8)

        var update = baseQuery(account: account)
        let status = SecItemUpdate(update as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            update[kSecValueData as String] = data
            return SecItemAdd(update as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func deleteKey(for account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The one account in use today.
    static let apolloAccount = "apollo-api-key"
}
