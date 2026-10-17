import Foundation
import Combine
import CryptoKit

/// Explicit AniList follows, local to each profile. Only public metadata is
/// retained. Personal selections are never included in API requests or logs.
@MainActor
final class NTVAnimeFollows: ObservableObject {
    static let shared = NTVAnimeFollows()
    static let limit = 200
    private static let maximumBytes = 1 << 20
    @Published private(set) var revision = 0
    private let defaults: UserDefaults
    private var cache: [Int: [NTVAnimeMedia]] = [:]
    private var cachedIDs: [Int: Set<Int>] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ profile: Int) -> String { "ntv.anime.follows.v1.p\(profile)" }

    func items(profile: Int = ProfileScopedDefaults.activeProfileID) -> [NTVAnimeMedia] {
        if let saved = cache[profile] { return saved }
        guard let data = defaults.data(forKey: key(profile)), data.count <= Self.maximumBytes,
              let decoded = try? JSONDecoder().decode([NTVAnimeMedia].self, from: data), decoded.count <= Self.limit else {
            cache[profile] = []; return []
        }
        var seen = Set<Int>()
        let values = decoded.filter { $0.canDisplay && $0.id <= Int(Int32.max) && seen.insert($0.id).inserted }.map(Self.sanitized)
        cache[profile] = values
        return values
    }
    func ids(profile: Int = ProfileScopedDefaults.activeProfileID) -> Set<Int> {
        if let ids = cachedIDs[profile] { return ids }
        let ids = Set(items(profile: profile).map(\.id))
        cachedIDs[profile] = ids
        return ids
    }
    func contains(_ id: Int, profile: Int = ProfileScopedDefaults.activeProfileID) -> Bool {
        ids(profile: profile).contains(id)
    }
    @discardableResult
    func toggle(_ media: NTVAnimeMedia, profile: Int = ProfileScopedDefaults.activeProfileID) -> Bool {
        guard media.canDisplay, media.id <= Int(Int32.max) else { return false }
        var values = items(profile: profile)
        if let index = values.firstIndex(where: { $0.id == media.id }) { values.remove(at: index) }
        else {
            guard values.count < Self.limit else { return false }
            values.insert(Self.sanitized(media), at: 0)
        }
        guard let data = try? JSONEncoder().encode(values), data.count <= Self.maximumBytes else { return false }
        defaults.set(data, forKey: key(profile))
        cache[profile] = values
        cachedIDs[profile] = Set(values.map(\.id))
        revision += 1
        return true
    }
    func forget(profile: Int) {
        defaults.removeObject(forKey: key(profile))
        cache.removeValue(forKey: profile); cachedIDs.removeValue(forKey: profile)
        revision += 1
    }
    private static func sanitized(_ value: NTVAnimeMedia) -> NTVAnimeMedia {
        NTVAnimeMedia(id: value.id, title: .init(romaji: value.displayTitle, english: nil, native: nil),
            coverImage: .init(large: value.artwork), bannerImage: value.backdrop,
            description: value.summary, episodes: value.episodes.flatMap { (1...100_000).contains($0) ? $0 : nil },
            format: ["TV", "TV_SHORT", "MOVIE", "OVA", "ONA", "SPECIAL", "MUSIC"].contains(value.format ?? "") ? value.format : nil,
            isAdult: false)
    }
}

/// Explicit provider hints only. "Animation" alone also includes Pixar and
/// other non-anime films: neither that genre nor a title spelling is evidence.
enum NTVAnimeDomain {
    private static let wordCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 2048
        return cache
    }()
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }
    private static func hasAnimeWord(_ value: String) -> Bool {
        guard value.utf8.count <= 512 else { return false }
        if let hit = wordCache.object(forKey: value as NSString) { return hit.boolValue }
        let text = normalized(value)
        let result = text == "japanese animation" || text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains { ["anime", "animes", "japanimation"].contains($0) }
        wordCache.setObject(NSNumber(value: result), forKey: value as NSString)
        return result
    }
    static func contains(_ item: MetaItem) -> Bool {
        if hasAnimeWord(item.type) { return true }
        let id = item.id.lowercased()
        if ["kitsu:", "anilist:", "mal:", "myanimelist:"].contains(where: { id.hasPrefix($0) }) { return true }
        return (item.genres ?? []).contains { hasAnimeWord($0) }
    }
    static func contains(_ catalog: ManifestCatalog) -> Bool {
        hasAnimeWord(catalog.type) || hasAnimeWord(catalog.id) || hasAnimeWord(catalog.name ?? "")
    }
}

/// Local classification learned when the viewer explicitly opens a result
/// from the anime space. Sparse IMDb metadata can otherwise lose its genre
/// when reconstructed from watch progress. No title, URL or token is stored.
/// Only an opaque digest is persisted (an addon ID can itself contain a URL).
/// Records are profile scoped, bounded, and never sent to AniList or sync.
@MainActor
final class NTVAnimeLibrary: ObservableObject {
    static let shared = NTVAnimeLibrary()
    @Published private(set) var revision = 0
    private let defaults: UserDefaults
    private var cached: [Int: Set<String>] = [:]
    private static let limit = 4096
    private let digests: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4096
        cache.totalCostLimit = 1 << 20
        return cache
    }()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ profile: Int) -> String { ProfileScopedDefaults.key("ntv.anime.identities.v1", profile) }
    private func identity(type: String, id: String) -> String {
        // Keep TMDB movie/show numeric IDs distinct; tv and series are aliases.
        let kind = ["series", "tv", "anime"].contains(type.lowercased()) ? "series" : type.lowercased()
        let raw = "ntv.anime.identity|" + kind + "|" + (MetaItem.upNextShowID(from: id) ?? id)
        if let hit = digests.object(forKey: raw as NSString) { return hit as String }
        let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        digests.setObject(digest as NSString, forKey: raw as NSString, cost: raw.utf8.count + 64)
        return digest
    }
    private func identities(_ profile: Int) -> Set<String> {
        if let hit = cached[profile] { return hit }
        let stored = (defaults.stringArray(forKey: key(profile)) ?? [])
            .prefix(Self.limit).filter { $0.count == 64 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } }
        let value = Set(stored)
        cached[profile] = value
        return value
    }
    func contains(_ item: MetaItem, profile: Int = ProfileScopedDefaults.activeProfileID) -> Bool {
        if NTVAnimeDomain.contains(item) { return true }
        let known = identities(profile)
        guard !known.isEmpty, item.id.utf8.count <= 512 else { return false }
        return known.contains(identity(type: item.type, id: item.id))
    }
    func remember(_ item: MetaItem, profile: Int = ProfileScopedDefaults.activeProfileID) {
        guard !item.id.isEmpty, item.id.utf8.count <= 512 else { return }
        let value = identity(type: item.type, id: item.id)
        var values = identities(profile)
        guard !values.contains(value), values.count < Self.limit else { return }
        values.insert(value)
        cached[profile] = values
        defaults.set(values.sorted(), forKey: key(profile))
        revision += 1
    }
    func forget(_ item: MetaItem, profile: Int = ProfileScopedDefaults.activeProfileID) {
        guard item.id.utf8.count <= 512 else { return }
        var values = identities(profile)
        guard values.remove(identity(type: item.type, id: item.id)) != nil else { return }
        cached[profile] = values
        defaults.set(values.sorted(), forKey: key(profile))
        revision += 1
    }
}
