import Foundation

/// This branch's presentation, independent of playback, accounts and addons.
/// The reference interface is preserved on backup/ntv-before-seanime-2026-10-17.
enum NTVInterfaceVariant {
    static let isSeanime = true

    /// A separate device-local key preserves the reference layout choice.
    /// Never include this value in an account sync or overwrite the old blob.
    static func navigationKey(profileID: Int) -> String {
        "ntv.seanime.navigation.v1.p\(profileID)"
    }

    static func navigation(profileID: Int, defaults: UserDefaults = .standard) -> NavigationPosition {
        defaults.string(forKey: navigationKey(profileID: profileID))
            .flatMap(NavigationPosition.init(rawValue:)) ?? .left
    }

    static func saveNavigation(_ position: NavigationPosition, profileID: Int,
                               defaults: UserDefaults = .standard) {
        defaults.set(position.rawValue, forKey: navigationKey(profileID: profileID))
    }
}
