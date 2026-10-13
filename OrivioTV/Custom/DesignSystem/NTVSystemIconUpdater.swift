import UIKit
import TVServices
import SwiftUI

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
@MainActor final class NTVSystemIconUpdater: ObservableObject {
    static let shared = NTVSystemIconUpdater()
    private static let iconName = "NTVSystemIcon"
    private static let migrationKey = "ntv.systemIconMigration.v1"
    private var running = false
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
        guard app.supportsAlternateIcons,
              NTVSystemIconManifest.declares(Self.iconName, in: Bundle.main.infoDictionary ?? [:]) else {
            #if DEBUG
            registrationState = "unavailable"
            #endif
            return
        }
        // The current system state is authoritative. A historical success flag
        // must not prevent re-registration after an update or icon reset.
        if app.alternateIconName == Self.iconName {
            #if DEBUG
            registrationState = "applied"
            #endif
            UserDefaults.standard.set(true, forKey: Self.migrationKey); return
        }
        running = true
        #if DEBUG
        registrationAttempts += 1
        registrationState = "applying"
        #endif
        defer { running = false }
        do {
            try await app.setAlternateIconName(Self.iconName)
            #if DEBUG
            registrationState = app.alternateIconName == Self.iconName ? "applied" : "mismatch"
            #endif
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
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
