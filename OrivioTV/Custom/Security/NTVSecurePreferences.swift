import Foundation
import Security
import CryptoKit

protocol NTVSecretStorage {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}

struct NTVKeychainStorage: NTVSecretStorage {
    private let service: String
    init(service: String = "ntv.private-preferences.v1") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false]
    }
    func read(_ key: String) throws -> Data? {
        var search = query(key)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StorageError.osStatus(status) }
        guard let data = result as? Data else { throw StorageError.unavailable }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let status = SecItemUpdate(query(key) as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(key)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StorageError.osStatus(addStatus) }
        } else if status != errSecSuccess { throw StorageError.osStatus(status) }
    }
    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.osStatus(status) }
    }
    enum StorageError: Error { case unavailable; case osStatus(OSStatus) }
}

/// Preserves legacy preference names and profile scope while moving credentials
/// to the device-local Keychain. Ordinary settings continue using UserDefaults.
final class NTVSecurePreferences {
    static let standard = NTVSecurePreferences(defaults: .standard, secrets: NTVKeychainStorage())
    private let defaults: UserDefaults
    private let secrets: any NTVSecretStorage
    init(defaults: UserDefaults, secrets: any NTVSecretStorage) {
        self.defaults = defaults
        self.secrets = secrets
    }

    static func isPrivate(_ key: String) -> Bool {
        ["orivio.session.v1", "orivio.stremio.authKey.v1", "orivio.trakt.tokens.v1",
         "orivio.trakt.secret.v1", "orivio.simkl.token.v1", "orivio.debrid.keys.v1",
         "orivio.debrid.rdrefresh.v1", "orivio.tmdb.settings.v1"].contains { key == $0 || key.hasPrefix($0 + ".p") }
    }
    private func revocationKey(_ key: String) -> String {
        "ntv.secure.revoked." + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func encode(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
    }
    private func decode(_ data: Data) throws -> Any? {
        (try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])?["value"]
    }
    func object(forKey key: String) -> Any? {
        guard Self.isPrivate(key) else { return defaults.object(forKey: key) }
        guard !defaults.bool(forKey: revocationKey(key)) else { return nil }
        do {
            if let data = try secrets.read(key) {
                guard let value = try decode(data) else { return nil }
                defaults.removeObject(forKey: key)
                return value
            }
            guard let legacy = defaults.object(forKey: key) else { return nil }
            let data = try encode(legacy)
            try secrets.write(data, key: key)
            guard try secrets.read(key) == data else { return nil }
            defaults.removeObject(forKey: key)
            return legacy
        } catch {
            // Never fall back to plaintext after a secure-storage failure.
            NSLog("[nTV Security] secure storage unavailable")
            return nil
        }
    }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func bool(forKey key: String) -> Bool { (object(forKey: key) as? Bool) ?? false }

    @discardableResult
    func set(_ value: Any?, forKey key: String) -> Bool {
        guard Self.isPrivate(key) else { defaults.set(value, forKey: key); return true }
        guard let value else { return removeObject(forKey: key) }
        do {
            let data = try encode(value)
            try secrets.write(data, key: key)
            guard try secrets.read(key) == data else { return false }
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: revocationKey(key))
            return true
        } catch {
            NSLog("[nTV Security] secure storage unavailable")
            return false
        }
    }
    @discardableResult
    func removeObject(forKey key: String) -> Bool {
        guard Self.isPrivate(key) else { defaults.removeObject(forKey: key); return true }
        // A failed Keychain deletion must never resurrect a signed-out session.
        defaults.set(true, forKey: revocationKey(key))
        defaults.removeObject(forKey: key)
        do { try secrets.remove(key); return true }
        catch { NSLog("[nTV Security] secure deletion pending"); return false }
    }
}
