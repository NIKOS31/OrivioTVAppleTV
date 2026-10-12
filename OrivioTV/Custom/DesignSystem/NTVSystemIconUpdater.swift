import UIKit

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
        if arguments.contains(where: { $0.hasSuffix("Demo") }) || arguments.contains("-ntvLaunchTest") { return }
        #endif
        let app = UIApplication.shared
        guard !running, app.applicationState == .active, app.supportsAlternateIcons,
              !UserDefaults.standard.bool(forKey: Self.migrationKey),
              let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let alternatives = icons["CFBundleAlternateIcons"] as? [String],
              alternatives.contains(Self.iconName) else { return }
        if app.alternateIconName == Self.iconName {
            UserDefaults.standard.set(true, forKey: Self.migrationKey); return
        }
        running = true
        defer { running = false }
        do {
            try await app.setAlternateIconName(Self.iconName)
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
        } catch {
            // Keep the migration pending when tvOS declines the operation.
            // No private device, account or provisioning data is logged.
        }
    }
}
