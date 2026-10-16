import Foundation
import Combine

/// Device-local search titles. Deliberately absent from account preferences,
/// iCloud and telemetry. Every profile uses its own key, even profile 1.
@MainActor
final class NTVRecentSearches: ObservableObject {
    static let shared = NTVRecentSearches()
    static let limit = 8
    @Published private(set) var revision = 0
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ profile: Int) -> String { ProfileScopedDefaults.key("ntv.search.recent.v1", profile) }

    /// Never persist a pasted addon URL, credential header or common token.
    /// The editor can still search it; history only accepts short title text.
    nonisolated static func title(_ input: String) -> String? {
        guard input.utf8.count <= 512, !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        let value = input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard (2...120).contains(value.count) else { return nil }
        let lower = value.lowercased()
        guard !lower.contains("://"), !lower.contains("www."), !lower.contains("@"),
              !["bearer ", "authorization", "password", "mot de passe", "api_key", "apikey", "api-key", "access_token", "refresh_token", "client_secret", "ghp_", "github_pat_"].contains(where: lower.contains),
              value.range(of: #"[A-Za-z0-9_\-+/=]{32,}|eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, options: .regularExpression) == nil else { return nil }
        return value
    }

    private static func identity(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    func queries(profile: Int) -> [String] {
        guard profile > 0, let data = defaults.data(forKey: key(profile)), data.count <= 8192,
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var seen = Set<String>()
        return values.prefix(Self.limit).compactMap(Self.title).filter { seen.insert(Self.identity($0)).inserted }
    }

    func record(_ input: String, profile: Int = ProfileScopedDefaults.activeProfileID) {
        guard profile > 0, let title = Self.title(input) else { return }
        let previous = queries(profile: profile)
        let next = [title] + previous.filter { Self.identity($0) != Self.identity(title) }
        write(Array(next.prefix(Self.limit)), profile: profile, previous: previous)
    }

    func remove(_ query: String, profile: Int) {
        let previous = queries(profile: profile)
        write(previous.filter { Self.identity($0) != Self.identity(query) }, profile: profile, previous: previous)
    }

    func clear(profile: Int) {
        guard profile > 0 else { return }
        defaults.removeObject(forKey: key(profile))
        revision += 1
    }

    private func write(_ values: [String], profile: Int, previous: [String]) {
        guard values != previous, let data = try? JSONEncoder().encode(values) else { return }
        if values.isEmpty { defaults.removeObject(forKey: key(profile)) }
        else { defaults.set(data, forKey: key(profile)) }
        revision += 1
    }
}
