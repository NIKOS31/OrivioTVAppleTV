import Foundation
import CryptoKit
import Combine

enum NTVResumePromptMode: String, CaseIterable {
    case interrupted, latest, off
    var title: String {
        switch self {
        case .interrupted: return "Après une interruption"
        case .latest: return "Dernier contenu en cours"
        case .off: return "Désactivée"
        }
    }
}

/// One suggestion per profile and app process. Merely changing tabs or coming
/// back from the player must not summon the same popup again.
@MainActor
final class NTVResumeSuggestion: ObservableObject {
    static let shared = NTVResumeSuggestion()
    @Published private(set) var revision = 0
    private var presentedProfiles = Set<Int>()
    private let defaults: UserDefaults
    private let processID: UUID
    private struct Marker: Codable {
        let digest: String
        let session: UUID
        let process: UUID
        let updatedAt: Date
    }
    init(defaults: UserDefaults = .standard, processID: UUID = UUID()) {
        self.defaults = defaults
        self.processID = processID
    }
    private func key(_ name: String, _ profile: Int) -> String {
        ProfileScopedDefaults.key("ntv.resume.\(name).v2", profile)
    }
    func mode(profile: Int) -> NTVResumePromptMode {
        NTVResumePromptMode(rawValue: defaults.string(forKey: key("mode", profile)) ?? "") ?? .latest
    }
    func setMode(_ mode: NTVResumePromptMode, profile: Int) {
        guard profile > 0, self.mode(profile: profile) != mode else { return }
        defaults.set(mode.rawValue, forKey: key("mode", profile))
        if mode == .off { defaults.removeObject(forKey: key("marker", profile)) }
        revision &+= 1
    }
    private func digest(id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func marker(profile: Int) -> Marker? {
        guard let data = defaults.data(forKey: key("marker", profile)), data.count <= 1024 else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }
    /// No media URL/title is persisted here, and periodic saves never publish to Home.
    func record(id: String, profile: Int, session: UUID, position: Double, duration: Double, now: Date = Date()) {
        guard profile > 0, mode(profile: profile) != .off, position.isFinite, duration.isFinite,
              duration > 0, position >= 30 else { return }
        guard position / duration < 0.95 else { clear(profile: profile, session: session); return }
        let value = Marker(digest: digest(id: id), session: session, process: processID, updatedAt: now)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key("marker", profile)) }
    }
    func clear(profile: Int, session: UUID) {
        guard marker(profile: profile)?.session == session else { return }
        defaults.removeObject(forKey: key("marker", profile))
    }
    func purge(profile: Int) {
        defaults.removeObject(forKey: key("marker", profile))
        defaults.removeObject(forKey: key("mode", profile))
        presentedProfiles.remove(profile)
        revision &+= 1
    }
    func hasPresented(profile: Int) -> Bool { presentedProfiles.contains(profile) }

    nonisolated static func latest(in items: [WatchProgress], now: Date) -> WatchProgress? {
        items.filter {
            $0.positionSeconds.isFinite && $0.durationSeconds.isFinite &&
            $0.positionSeconds >= 30 && $0.durationSeconds > 0 && $0.fraction < 0.95 &&
            $0.updatedAt <= now.addingTimeInterval(60) &&
            $0.updatedAt >= now.addingTimeInterval(-30 * 86400) &&
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.max {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt
        }
    }

    func claim(profile: Int, items: [WatchProgress], now: Date = Date()) -> WatchProgress? {
        guard profile > 0, !presentedProfiles.contains(profile) else { return nil }
        let candidate: WatchProgress?
        switch mode(profile: profile) {
        case .off: return nil
        case .latest: candidate = Self.latest(in: items, now: now)
        case .interrupted:
            guard let marker = marker(profile: profile), marker.process != processID,
                  marker.updatedAt >= now.addingTimeInterval(-30 * 86400),
                  marker.updatedAt <= now.addingTimeInterval(60) else { return nil }
            candidate = Self.latest(in: items.filter { digest(id: $0.id) == marker.digest }, now: now)
        }
        guard let candidate else { return nil }
        defaults.removeObject(forKey: key("marker", profile))
        presentedProfiles.insert(profile)
        return candidate
    }
}
