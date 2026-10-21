import UIKit
import TVServices
import SwiftUI

/// actool's standalone tvOS output uses an array, while Xcode's merged
/// Info.plist can use keyed entries. Inspect the compiled declaration rather
/// than assuming the shape of the intermediate compiler output.
enum NTVSystemIconManifest {
    static func primaryName(in info: [String: Any]) -> String? {
        guard let icons = info["CFBundleIcons"] as? [String: Any] else { return nil }
        if let name = icons["CFBundlePrimaryIcon"] as? String { return name }
        return (icons["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconName"] as? String
    }
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

enum NTVSystemIconMigration {
    static func steps(current: String?, legacyRegistration: Bool, refreshed: Bool) -> [String?] {
        if current != nil { return [nil] }
        // A primary name alone does not prove that the switcher's cached image
        // was updated. Re-register legacy installations once through UIKit.
        return legacyRegistration && !refreshed ? ["NTVSystemIcon", nil] : []
    }
}

/// Restore the supplied n as the primary system icon, including its large
/// rendition. Build38's alternate small stack did not refresh the switcher
/// rendition on the user's physical Apple TV.
/// This leaves the app's bundle ID, signing account and local data untouched.
@MainActor final class NTVSystemIconUpdater: ObservableObject {
    static let shared = NTVSystemIconUpdater()
    private static let migrationKey = "ntv.systemIconMigration.v3"
    private static let legacyMigrationKey = "ntv.systemIconMigration.v2"
    private var running = false
    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ntvPrimaryIconRefreshFixture") {
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationKey)
            UserDefaults.standard.removeObject(forKey: Self.migrationKey)
        }
        #endif
    }
    #if DEBUG
    @Published private(set) var registrationState = "idle"
    @Published private(set) var registrationAttempts = 0
    var registrationValue: String {
        registrationState + "#" + (UIApplication.shared.alternateIconName ?? "primary") + "#\(registrationAttempts)"
    }
    #endif

    func applyIfNeeded() async {
        #if DEBUG
        // UI fixtures must not invoke a system icon confirmation or alter
        // the simulator's Home Screen while the remote journey is running.
        let arguments = ProcessInfo.processInfo.arguments
        let iconProbe = arguments.contains("-ntvIconRegistrationProbe")
        if !iconProbe && (arguments.contains(where: { $0.hasSuffix("Demo") }) || arguments.contains("-ntvLaunchTest") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) { return }
        #endif
        let app = UIApplication.shared
        guard !running, app.applicationState == .active else { return }
        var targetIcon: String? = nil
        #if DEBUG
        // Seed the real build38 alternate state before the primary migration
        // in the system UI test. This path is absent from production.
        if arguments.contains("-ntvLegacyIconFixture") { targetIcon = "NTVSystemIcon" }
        #endif
        guard app.supportsAlternateIcons,
              NTVSystemIconManifest.primaryName(in: Bundle.main.infoDictionary ?? [:]) == "NTVPrimaryIconV2",
              NTVSystemIconManifest.declares("NTVSystemIcon", in: Bundle.main.infoDictionary ?? [:]),
              targetIcon.map({ NTVSystemIconManifest.declares($0, in: Bundle.main.infoDictionary ?? [:]) }) ?? true else {
            #if DEBUG
            registrationState = "unavailable"
            #endif
            return
        }
        let steps: [String?]
        if let targetIcon {
            steps = app.alternateIconName == targetIcon ? [] : [targetIcon]
        } else {
            steps = NTVSystemIconMigration.steps(
                current: app.alternateIconName,
                legacyRegistration: UserDefaults.standard.bool(forKey: Self.legacyMigrationKey),
                refreshed: UserDefaults.standard.bool(forKey: Self.migrationKey)
            )
        }
        if steps.isEmpty {
            #if DEBUG
            registrationState = "applied"
            #endif
            if targetIcon == nil { UserDefaults.standard.set(true, forKey: Self.migrationKey) }
            return
        }
        running = true
        #if DEBUG
        registrationState = "applying"
        #endif
        defer { running = false }
        do {
            for icon in steps {
                #if DEBUG
                registrationAttempts += 1
                #endif
                try await app.setAlternateIconName(icon)
                guard app.alternateIconName == icon else {
                    #if DEBUG
                    registrationState = "mismatch"
                    #endif
                    return
                }
            }
            #if DEBUG
            registrationState = app.alternateIconName == targetIcon ? "applied" : "mismatch"
            #endif
            if targetIcon == nil { UserDefaults.standard.set(true, forKey: Self.migrationKey) }
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            #if DEBUG
            registrationState = "failed"
            #endif
            // Keep the migration pending when tvOS declines the operation.
            // No private device, account or provisioning data is logged.
        }
    }
}

extension View {
    @ViewBuilder func ntvSystemIconRegistrationProbe() -> some View {
        #if DEBUG
        self.overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("-ntvIconRegistrationProbe") {
                NTVSystemIconRegistrationProbe()
            }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct NTVSystemIconRegistrationProbe: View {
    @ObservedObject private var updater = NTVSystemIconUpdater.shared
    var body: some View {
        Text("Icône nTV")
            .font(.caption)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("ntv.systemIcon.registration")
            .accessibilityValue(updater.registrationValue)
    }
}
#endif
