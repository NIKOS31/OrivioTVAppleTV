import UIKit
import TVServices

/// actool's standalone tvOS output uses an array, while Xcode's merged
/// Info.plist can use keyed entries. Inspect the compiled declaration rather
/// than assuming the shape of the intermediate compiler output.
enum NTVSystemIconManifest {
    static func declares(_ name: String, in info: [String: Any]) -> Bool {
        guard let icons = info["CFBundleIcons"] as? [String: Any] else { return false }
        if let names = icons["CFBundleAlternateIcons"] as? [String] {
            return names.contains(name)
        }
        guard let alternatives = icons["CFBundleAlternateIcons"] as? [String: Any],
              let entry = alternatives[name] as? [String: Any] else { return false }
        return entry["CFBundleIconName"] as? String == name
    }
}

/// Re-register the supplied n through Apple's supported icon-change API.
/// This leaves the app's bundle ID, signing account and local data untouched.
@MainActor final class NTVSystemIconUpdater {
    static let shared = NTVSystemIconUpdater()
    private static let iconName = "NTVSystemIcon"
    private static let migrationKey = "ntv.systemIconMigration.v1"
    private var running = false

    func applyIfNeeded() async {
        #if DEBUG
        // UI fixtures must not invoke a system icon confirmation or alter
        // the simulator's Home Screen while the remote journey is running.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasSuffix("Demo") }) || arguments.contains("-ntvLaunchTest") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        let app = UIApplication.shared
        guard !running, app.applicationState == .active, app.supportsAlternateIcons,
              NTVSystemIconManifest.declares(Self.iconName, in: Bundle.main.infoDictionary ?? [:]) else { return }
        // The current system state is authoritative. A historical success flag
        // must not prevent re-registration after an update or icon reset.
        if app.alternateIconName == Self.iconName {
            UserDefaults.standard.set(true, forKey: Self.migrationKey); return
        }
        running = true
        defer { running = false }
        do {
            try await app.setAlternateIconName(Self.iconName)
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            // Keep the migration pending when tvOS declines the operation.
            // No private device, account or provisioning data is logged.
        }
    }
}
