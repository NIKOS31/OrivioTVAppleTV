import Foundation
import Security

/// Device-local, per-profile credentials. No defaults, iCloud synchronisation,
/// account-backend payload or diagnostics contain an OAuth token.
struct NTVTwitchCredentials {
    private let account: String
    private static let service = "ntv.twitch.oauth.v1"

    init(clientID: String, profileID: Int) {
        account = "\(clientID).profile.\(profileID)"
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> NTVTwitchTokens? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let tokens = try? JSONDecoder().decode(NTVTwitchTokens.self, from: data) else {
            throw NTVTwitchError.secureStorage
        }
        return tokens
    }

    func save(_ tokens: NTVTwitchTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw NTVTwitchError.secureStorage }
        } else if status != errSecSuccess { throw NTVTwitchError.secureStorage }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NTVTwitchError.secureStorage }
    }
}
