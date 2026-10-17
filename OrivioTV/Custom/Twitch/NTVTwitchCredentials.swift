import Foundation
import CryptoKit

/// OAuth tokens remain device-local. Defaults hold only a revocation marker,
/// never credentials. A failed Keychain deletion must survive reopening the UI.
struct NTVTwitchCredentials {
    private let account: String
    private let defaults: UserDefaults
    private let secrets: any NTVSecretStorage

    init(clientID: String, profileID: Int, ownerScope: String = "local",
         defaults: UserDefaults = .standard,
         secrets: any NTVSecretStorage = NTVKeychainStorage(service: "ntv.twitch.oauth.v1")) {
        let base = "\(clientID).profile.\(profileID)"
        account = ownerScope == "local" ? base : base + ".owner." + Self.digest(ownerScope)
        self.defaults = defaults
        self.secrets = secrets
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var revocationKey: String { "ntv.twitch.revoked." + Self.digest(account) }

    func load() throws -> NTVTwitchTokens? {
        guard !defaults.bool(forKey: revocationKey) else { return nil }
        do {
            guard let data = try secrets.read(account) else { return nil }
            return try JSONDecoder().decode(NTVTwitchTokens.self, from: data)
        } catch { throw NTVTwitchError.secureStorage }
    }

    func save(_ tokens: NTVTwitchTokens) throws {
        do {
            try secrets.write(JSONEncoder().encode(tokens), key: account)
            // Clear the marker only after a new authorized session is stored.
            defaults.removeObject(forKey: revocationKey)
        } catch { throw NTVTwitchError.secureStorage }
    }

    func remove() throws {
        defaults.set(true, forKey: revocationKey)
        do { try secrets.remove(account) }
        catch { throw NTVTwitchError.secureStorage }
    }
}
