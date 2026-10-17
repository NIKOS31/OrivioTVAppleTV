import Foundation

/// One suggestion per profile and app process. Merely changing tabs or coming
/// back from the player must not summon the same popup again.
@MainActor
final class NTVResumeSuggestion {
    static let shared = NTVResumeSuggestion()
    private var presentedProfiles = Set<Int>()
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
        guard profile > 0, !presentedProfiles.contains(profile),
              let candidate = Self.latest(in: items, now: now) else { return nil }
        presentedProfiles.insert(profile)
        return candidate
    }
}
