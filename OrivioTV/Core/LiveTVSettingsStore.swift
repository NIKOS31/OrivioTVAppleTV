import Foundation
import CryptoKit

/// Location + language preferences for Live TV. When set, the embedded IPTV
/// list is loaded from iptv-org's per-country / per-language playlist instead
/// of the giant global one, so channels that don't apply to the viewer are
/// simply not there. Shared singleton (like PerformanceSettingsStore) so both
/// the settings pane and the Live TV tab read it without extra wiring.
@MainActor
final class LiveTVSettingsStore: ObservableObject {
    static let shared = LiveTVSettingsStore()

    /// Whether the Live TV tab is shown in the sidebar at all.
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    /// ISO-3166 alpha-2 lowercase (iptv-org country file), "" = all.
    @Published var countryCode: String { didSet { UserDefaults.standard.set(countryCode, forKey: Self.countryKey) } }
    /// ISO-639-3 lowercase (iptv-org language file), "" = all.
    @Published var languageCode: String { didSet { UserDefaults.standard.set(languageCode, forKey: Self.langKey) } }
    /// User-supplied M3U playlist URL. When set (non-blank), it REPLACES the
    /// built-in iptv-org source outright — no merging, and the location /
    /// language filters don't apply (those are paths into iptv-org's playlist
    /// tree, meaningless against someone else's server). Cleared = the
    /// built-in list is right back; nothing about it is forgotten.
    @Published var customPlaylistURL: String {
        didSet {
            NTVSecurePreferences.standard.set(customPlaylistURL, forKey: Self.customURLKey)
            if oldValue != customPlaylistURL {
                destinations = Self.readDestinations(customPlaylistURL)
                untypedM3USection = Self.readUntyped(customPlaylistURL)
            }
        }
    }
    @Published var destinations: Set<NTVIPTVSection> {
        didSet { UserDefaults.standard.set(destinations.map(\.rawValue).sorted(), forKey: Self.routingKey(customPlaylistURL)) }
    }
    @Published var untypedM3USection: NTVIPTVSection {
        didSet { UserDefaults.standard.set(untypedM3USection.rawValue, forKey: Self.routingKey(customPlaylistURL) + ".untyped") }
    }
    private static func routingKey(_ url: String) -> String { "ntv.iptv.routing.v1." + NTVIPTVConfiguration.digest(url) }
    private static func readDestinations(_ url: String) -> Set<NTVIPTVSection> {
        guard let raw = UserDefaults.standard.array(forKey: routingKey(url)) as? [String] else { return [.tv] }
        return Set(raw.compactMap(NTVIPTVSection.init(rawValue:)))
    }
    private static func readUntyped(_ url: String) -> NTVIPTVSection {
        NTVIPTVSection(rawValue: UserDefaults.standard.string(forKey: routingKey(url) + ".untyped") ?? "") ?? .tv
    }
    var routingFingerprint: String {
        NTVIPTVConfiguration.digest(customPlaylistURL) + "#" + destinations.map(\.rawValue).sorted().joined(separator: ",") + "#" + untypedM3USection.rawValue
    }
    var configuration: NTVIPTVConfiguration? {
        NTVIPTVConfiguration(playlist: customPlaylistURL, destinations: destinations, untyped: untypedM3USection)
    }
    var localCatalogAddon: InstalledAddon? {
        guard usesCustomPlaylist, let configuration else { return nil }
        return configuration.catalogAddon

    }

    private static let enabledKey = "orivio.livetv.enabled.v1"
    private static let countryKey = "orivio.livetv.country.v1"
    private static let langKey = "orivio.livetv.language.v1"
    private static let customURLKey = "orivio.livetv.customurl.v1"

    private init() {
        // Default ON (the tab ships enabled); only an explicit false hides it.
        enabled = (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
        countryCode = UserDefaults.standard.string(forKey: Self.countryKey) ?? ""
        languageCode = UserDefaults.standard.string(forKey: Self.langKey) ?? ""
        let saved = NTVSecurePreferences.standard.string(forKey: Self.customURLKey) ?? ""
        destinations = Self.readDestinations(saved)
        untypedM3USection = Self.readUntyped(saved)
        customPlaylistURL = saved
    }

    static let base = "https://iptv-org.github.io/iptv"

    /// Whether a custom playlist is set and therefore replaces the built-in one.
    var usesCustomPlaylist: Bool {
        !customPlaylistURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The playlist URL for an IPTV provider's login (the Xtream Codes API
    /// nearly every paid provider hands out as server + username + password).
    /// Their `get.php` endpoint serves the subscriber's whole channel list as
    /// an ordinary M3U, so the result is stored and loaded exactly like a
    /// pasted playlist URL. HLS output (`m3u8`) so channels open in the
    /// native player. nil when the server isn't a usable URL.
    nonisolated static func providerPlaylistURL(server: String, username: String, password: String) -> String? {
        var base = server.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        // Credentials must travel over TLS, including a bare server address.
        if !base.contains("://") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base), components.query == nil, components.fragment == nil,
              let origin = components.url, NTVIPTVConfiguration.secure(origin),
              !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty,
              username.utf8.count <= 4096, password.utf8.count <= 4096 else { return nil }
        if origin.lastPathComponent.lowercased() != "get.php" {
            components.path += "/get.php"
        }
        components.queryItems = [
            URLQueryItem(name: "username", value: username.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "m3u8"),
        ]
        // URLComponents leaves `+` bare, and servers decode a bare `+` in a
        // query as a space — a password containing one would never match.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let result = components.url?.absoluteString, result.utf8.count <= 16_384 else { return nil }
        return result
    }

    /// Paths and queries may both carry credentials.
    var customPlaylistDisplayURL: String {
        guard let url = URL(string: customPlaylistURL), let host = url.host else { return "Source IPTV configurée" }
        return host + (url.port.map { ":\($0)" } ?? "") + "/…"
    }

    /// Playlist to load. A CUSTOM playlist wins over everything — that's its
    /// contract: adding one takes over from the built-in list entirely.
    /// Otherwise LANGUAGE wins over location: a preferred language means
    /// "only channels in that language, wherever they're from" — so a US viewer
    /// who prefers English still sees BBC (English/UK) but not Al Majd
    /// (Arabic/Saudi). Location matters only when no language is chosen.
    var primaryPlaylistURL: String {
        if usesCustomPlaylist { return customPlaylistURL.trimmingCharacters(in: .whitespaces) }
        if !languageCode.isEmpty { return "\(Self.base)/languages/\(languageCode).m3u" }
        if !countryCode.isEmpty { return "\(Self.base)/countries/\(countryCode).m3u" }
        return M3UService.iptvOrgURL
    }

    /// Countries where each language is a primary/common language — the curated
    /// safety-net list. Used to filter the global playlist by a channel's
    /// country code if the per-language iptv-org playlist can't be loaded, so
    /// non-matching-language channels still get hidden.
    static let languageCountries: [String: Set<String>] = [
        "eng": ["us", "gb", "ca", "au", "ie", "nz", "za", "in", "jm", "tt", "ph", "sg", "ng", "ke", "gh", "bs", "bb", "bz", "gy"],
        "spa": ["es", "mx", "ar", "co", "cl", "pe", "ve", "ec", "gt", "cu", "bo", "do", "hn", "py", "sv", "ni", "cr", "pa", "uy", "pr"],
        "fra": ["fr", "ca", "be", "ch", "lu", "mc", "sn", "ci", "cd", "cm", "ml", "ht", "dz", "ma", "tn"],
        "deu": ["de", "at", "ch", "li", "lu"],
        "ita": ["it", "sm", "va", "ch"],
        "por": ["pt", "br", "ao", "mz", "cv"],
        "nld": ["nl", "be", "sr", "aw"],
        "rus": ["ru", "by", "kz", "kg", "md"],
        "tur": ["tr", "cy"],
        "pol": ["pl"],
        "ara": ["sa", "ae", "eg", "iq", "jo", "kw", "lb", "ly", "ma", "om", "qa", "sy", "tn", "ye", "dz", "bh", "sd", "ps"],
        "hin": ["in"],
        "jpn": ["jp"],
        "kor": ["kr", "kp"],
        "zho": ["cn", "tw", "hk", "sg", "mo"],
    ]

    func countriesForLanguage(_ code: String) -> Set<String> {
        Self.languageCountries[code] ?? []
    }

    struct Option: Identifiable { let code: String; let name: String; var id: String { code } }

    static let countries: [Option] = [
        .init(code: "", name: "All countries"),
        .init(code: "us", name: "United States"),
        .init(code: "gb", name: "United Kingdom"),
        .init(code: "ca", name: "Canada"),
        .init(code: "au", name: "Australia"),
        .init(code: "ie", name: "Ireland"),
        .init(code: "nz", name: "New Zealand"),
        .init(code: "in", name: "India"),
        .init(code: "de", name: "Germany"),
        .init(code: "fr", name: "France"),
        .init(code: "es", name: "Spain"),
        .init(code: "it", name: "Italy"),
        .init(code: "pt", name: "Portugal"),
        .init(code: "nl", name: "Netherlands"),
        .init(code: "se", name: "Sweden"),
        .init(code: "no", name: "Norway"),
        .init(code: "dk", name: "Denmark"),
        .init(code: "pl", name: "Poland"),
        .init(code: "ru", name: "Russia"),
        .init(code: "tr", name: "Turkey"),
        .init(code: "br", name: "Brazil"),
        .init(code: "mx", name: "Mexico"),
        .init(code: "ar", name: "Argentina"),
        .init(code: "jp", name: "Japan"),
        .init(code: "kr", name: "South Korea"),
    ]

    static let languages: [Option] = [
        .init(code: "", name: "All languages"),
        .init(code: "eng", name: "English"),
        .init(code: "spa", name: "Spanish"),
        .init(code: "fra", name: "French"),
        .init(code: "deu", name: "German"),
        .init(code: "ita", name: "Italian"),
        .init(code: "por", name: "Portuguese"),
        .init(code: "nld", name: "Dutch"),
        .init(code: "rus", name: "Russian"),
        .init(code: "tur", name: "Turkish"),
        .init(code: "pol", name: "Polish"),
        .init(code: "ara", name: "Arabic"),
        .init(code: "hin", name: "Hindi"),
        .init(code: "jpn", name: "Japanese"),
        .init(code: "kor", name: "Korean"),
        .init(code: "zho", name: "Chinese"),
    ]

}

enum NTVIPTVSection: String, Codable, CaseIterable, Hashable, Sendable {
    case tv, movie, series
    var title: String {
        switch self { case .tv: return "TV"; case .movie: return "Films"; case .series: return "Séries" }
    }
    static func declared(_ value: String?) -> Self? {
        switch value?.lowercased() {
        case "live", "tv": return .tv
        case "movie", "movies", "vod": return .movie
        case "series": return .series
        default: return nil
        }
    }
}

/// Credentials are read from the existing encrypted preference, used only on
/// this device and never encoded into the internal addon URL or content IDs.
struct NTVIPTVConfiguration: Sendable {
    static let bridgeURL = "ntv-iptv://local"
    static let idPrefix = "ntv.iptv."
    let playlist: String
    let destinations: Set<NTVIPTVSection>
    let untyped: NTVIPTVSection
    let identity: String
    var prefix: String { Self.idPrefix + identity + "." }
    var isXtream: Bool { credentials != nil }
    var catalogAddon: InstalledAddon? {
        let catalogs = [NTVIPTVSection.movie, .series].filter { destinations.contains($0) }.map {
            ManifestCatalog(type: $0.rawValue, id: $0.rawValue, name: "IPTV · " + $0.title,
                extra: nil, extraRequired: nil, extraSupported: ["skip", "search"])
        }
        guard !catalogs.isEmpty else { return nil }
        return InstalledAddon(manifestURL: NTVIPTVConfiguration.bridgeURL,
            manifest: AddonManifest(id: "ntv.local.iptv", name: "Mon IPTV", version: "1", description: nil, logo: nil,
                types: catalogs.map(\.type), idPrefixes: [prefix],
                catalogs: catalogs, resources: [.simple("meta"), .simple("stream")]))
    }

    init?(playlist: String, destinations: Set<NTVIPTVSection>, untyped: NTVIPTVSection) {
        let value = playlist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), Self.secure(url), value.utf8.count <= 16_384 else { return nil }
        self.playlist = value; self.destinations = destinations; self.untyped = untyped
        identity = Self.digest(value)
    }
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && NTVAddonTransportPolicy.permits(url) && url.fragment == nil
            && url.absoluteString.utf8.count <= 16_384
            && !url.absoluteString.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    private var credentials: (URL, String, String)? {
        guard let url = URL(string: playlist), url.lastPathComponent.lowercased() == "get.php",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let user = items.first(where: { $0.name == "username" })?.value, !user.isEmpty,
              let password = items.first(where: { $0.name == "password" })?.value, !password.isEmpty,
              var base = URLComponents(url: url.deletingLastPathComponent(), resolvingAgainstBaseURL: false) else { return nil }
        base.query = nil; base.fragment = nil
        guard let origin = base.url else { return nil }
        return (origin, user, password)
    }
    func apiURL(action: String? = nil, seriesID: String? = nil) throws -> URL {
        guard action == nil || ["get_vod_streams", "get_series", "get_series_info"].contains(action!),
              let (base, user, password) = credentials,
              var parts = URLComponents(url: base.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false) else {
            throw StremioAPIError.invalidResponse
        }
        parts.queryItems = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: password)]
        if let action { parts.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        if let seriesID {
            guard Self.providerID(seriesID) else { throw StremioAPIError.invalidResponse }
            parts.queryItems?.append(URLQueryItem(name: "series_id", value: seriesID))
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url, Self.secure(url) else { throw StremioAPIError.invalidResponse }
        return url
    }
    static func providerID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    func mediaURL(section: NTVIPTVSection, id: String, ext: String) -> String? {
        guard section != .tv, Self.providerID(id), let (base, user, password) = credentials,
              ["mp4", "mkv", "m3u8", "ts", "avi", "mov", "webm"].contains(ext.lowercased()),
              var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let segments = [section.rawValue, user, password, id + "." + ext.lowercased()]
        let encoded = segments.compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
        guard encoded.count == segments.count else { return nil }
        parts.percentEncodedPath = parts.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map(String.init).reduce("") { $0 + "/" + $1 } + "/" + encoded.joined(separator: "/")
        return parts.url?.absoluteString
    }
    func section(for channel: M3UChannel) -> NTVIPTVSection {
        if let declared = channel.declaredSection { return declared }
        let segments = URL(string: channel.url)?.pathComponents.map { $0.lowercased() } ?? []
        for segment in segments {
            if segment == "movie" { return .movie }
            if segment == "series" { return .series }
            if segment == "live" { return .tv }
        }
        return untyped
    }
    static func isBridge(_ addon: InstalledAddon) -> Bool {
        addon.manifestURL == bridgeURL && addon.manifest.id == "ntv.local.iptv"
    }
    @MainActor static func current(for addon: InstalledAddon) throws -> Self {
        guard let configuration = LiveTVSettingsStore.shared.configuration,
              addon.manifest.idPrefixes == [configuration.prefix] else { throw CancellationError() }
        return configuration
    }
    @MainActor var isCurrent: Bool {
        guard let current = LiveTVSettingsStore.shared.configuration else { return false }
        return current.identity == identity && current.destinations == destinations && current.untyped == untyped
    }
}

/// This is a local catalog adapter, not a server. Only metadata and playlist
/// text are fetched; media is passed to the existing native playback engines.
actor NTVIPTVCatalogService {
    static let shared = NTVIPTVCatalogService()
    private static let network = NTVSharedWorkPool<Data>(limit: 2)
    private static let session = NTVAddonTransportPolicy.makeSession(configuration: .ephemeral)
    private struct Record {
        var meta: MetaItem
        var streams: [String: Stream]
    }
    private struct Catalog {
        let records: [Record]
        let loadedAt: Date
    }
    private var cache: [String: Catalog] = [:]
    private var detailCache: [String: (record: Record, loadedAt: Date)] = [:]
    private var detailOrder: [String] = []
    private var activeIdentity: String?
    private let load: @Sendable (URL) async throws -> Data

    init(load: @escaping @Sendable (URL) async throws -> Data = { try await NTVIPTVCatalogService.body($0) }) {
        self.load = load
    }

    private func scope(_ config: NTVIPTVConfiguration) {
        if activeIdentity != config.identity {
            cache = [:]; detailCache = [:]; detailOrder = []; activeIdentity = config.identity
        }
    }
    private static func body(_ url: URL) async throws -> Data {
        guard NTVIPTVConfiguration.secure(url) else { throw StremioAPIError.badURL("iptv") }
        let key = NTVIPTVConfiguration.digest(url.absoluteString)
        return try await network.value(for: key) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 16 << 20)
            guard (200..<300).contains(response.statusCode) else { throw StremioAPIError.badResponse(response.statusCode) }
            return data
        }
    }
    private static func string(_ value: Any?) -> String? {
        let result = value as? String ?? (value as? NSNumber)?.stringValue
        guard let result, !result.isEmpty, result.utf8.count <= 4096 else { return nil }
        return result
    }
    private static func artwork(_ value: Any?) -> String? {
        guard let raw = string(value), let url = URL(string: raw),
              NTVIPTVConfiguration.secure(url) else { return nil }
        return raw
    }
    private static func withVideos(_ videos: [MetaVideo], in meta: MetaItem) -> MetaItem {
        MetaItem(id: meta.id, type: meta.type, name: meta.name, poster: meta.poster, background: meta.background,
            logo: meta.logo, description: meta.description, releaseInfo: meta.releaseInfo, imdbRating: meta.imdbRating,
            runtime: meta.runtime, genres: meta.genres, cast: meta.cast, videos: videos,
            posterFallback: meta.posterFallback, released: meta.released)
    }
    func validateAccount(config: NTVIPTVConfiguration) async throws {
        let data = try await load(config.apiURL())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let info = object?["user_info"] as? [String: Any],
              Self.string(info["auth"]) == "1", Self.string(info["status"])?.lowercased() == "active" else {
            throw StremioAPIError.invalidResponse
        }
    }
    private static func parseProvider(_ data: Data, config: NTVIPTVConfiguration, section: NTVIPTVSection) throws -> [Record] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw StremioAPIError.invalidResponse }
        guard rows.count <= 10_000 else { throw StremioAPIError.responseTooLarge }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let number = string(row[section == .movie ? "stream_id" : "series_id"]),
                  NTVIPTVConfiguration.providerID(number), let name = string(row["name"]) else { return nil }
            let id = config.prefix + section.rawValue + "." + number
            guard seen.insert(id).inserted else { return nil }
            let meta = MetaItem(id: id, type: section.rawValue, name: name,
                poster: artwork(row["stream_icon"] ?? row["cover"]),
                background: artwork((row["backdrop_path"] as? [String])?.first),
                description: string(row["plot"]), imdbRating: string(row["rating"]),
                released: string(row["releaseDate"] ?? row["release_date"]))
            let stream = section == .movie ? config.mediaURL(section: .movie, id: number, ext: string(row["container_extension"]) ?? "mp4") : nil
            return Record(meta: meta, streams: stream.map { [id: Stream(name: "IPTV", title: name, description: nil,
                url: $0, infoHash: nil, behaviorHints: nil)] } ?? [:])
        }
    }
    private static let episodePattern = try! NSRegularExpression(pattern: #"^(.*?)\s+[sS](\d{1,3})[eE](\d{1,4})(?:\s*[-–:]?\s*(.*))?$"#)
    private static func parseM3U(_ text: String, config: NTVIPTVConfiguration, section: NTVIPTVSection) throws -> [Record] {
        let channels = M3UService.parse(text)
        guard channels.count <= 50_000 else { throw StremioAPIError.responseTooLarge }
        var order: [String] = [], records: [String: Record] = [:], videos: [String: [MetaVideo]] = [:]
        var episodeStreams: [String: [String: Stream]] = [:]
        for channel in channels where config.section(for: channel) == section {
            guard channel.name.utf8.count <= 4096, let url = URL(string: channel.url), NTVIPTVConfiguration.secure(url) else { continue }
            let leafID = config.prefix + section.rawValue + "." + NTVIPTVConfiguration.digest(channel.url)
            guard channel.options.unsupportedDRMReason == nil else { continue }
            let hints = channel.options.requestHeaders.map { StreamBehaviorHints(proxyHeaders: StreamProxyHeaders(request: $0)) }
            let stream = Stream(name: "IPTV", title: channel.name, description: nil, url: channel.url,
                infoHash: nil, behaviorHints: hints)
            if section == .movie {
                guard records[leafID] == nil else { continue }
                order.append(leafID)
                records[leafID] = Record(meta: MetaItem(id: leafID, type: "movie", name: channel.name, poster: artwork(channel.logo)), streams: [leafID: stream])
            } else if section == .series {
                let name = channel.name as NSString
                guard let match = episodePattern.firstMatch(in: channel.name, range: NSRange(location: 0, length: name.length)),
                      let season = Int(name.substring(with: match.range(at: 2))),
                      let episode = Int(name.substring(with: match.range(at: 3))), episode > 0 else { continue }
                let title = name.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                let showID = config.prefix + "series." + NTVIPTVConfiguration.digest(title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))
                let video = MetaVideo(id: leafID, title: channel.name, season: season, episode: episode)
                if episodeStreams[showID]?[leafID] == nil {
                    videos[showID, default: []].append(video)
                    episodeStreams[showID, default: [:]][leafID] = stream
                }
                if records[showID] == nil {
                    order.append(showID)
                    records[showID] = Record(meta: MetaItem(id: showID, type: "series", name: title, poster: artwork(channel.logo), videos: []), streams: [:])
                }
            }
        }
        guard order.count <= 10_000 else { throw StremioAPIError.responseTooLarge }
        return order.compactMap { id in
            guard var record = records[id] else { return nil }
            if let episodes = videos[id] {
                record.meta = withVideos(episodes.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }, in: record.meta)
                record.streams = episodeStreams[id] ?? [:]
            }
            return record
        }
    }
    private func records(_ config: NTVIPTVConfiguration, section: NTVIPTVSection) async throws -> [Record] {
        scope(config)
        guard config.destinations.contains(section), section != .tv else { return [] }
        let key = config.identity + "." + section.rawValue + "." + config.untyped.rawValue
        if let cached = cache[key], Date().timeIntervalSince(cached.loadedAt) < 300 { return cached.records }
        let data: Data
        let value: [Record]
        if config.isXtream {
            data = try await load(config.apiURL(action: section == .movie ? "get_vod_streams" : "get_series"))
            value = try Self.parseProvider(data, config: config, section: section)
        } else {
            guard let url = URL(string: config.playlist) else { throw StremioAPIError.invalidResponse }
            data = try await load(url)
            guard let text = String(data: data, encoding: .utf8), text.contains("#EXTINF") else { throw StremioAPIError.invalidResponse }
            value = try Self.parseM3U(text, config: config, section: section)
        }
        try Task.checkCancellation()
        guard activeIdentity == config.identity else { throw CancellationError() }
        // At most the film and series catalogs of the active configuration.
        cache = cache.filter { $0.key.hasPrefix(config.identity + ".") && Date().timeIntervalSince($0.value.loadedAt) < 300 }
        if cache.count >= 2 { cache.removeValue(forKey: cache.keys.sorted().first!) }
        cache[key] = Catalog(records: value, loadedAt: Date())
        return value
    }
    func catalog(config: NTVIPTVConfiguration, type: String, search: String?, skip: Int?) async throws -> [MetaItem] {
        guard let section = NTVIPTVSection(rawValue: type) else { return [] }
        let records = try await records(config, section: section)
        let query = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? records : records.filter { $0.meta.name.localizedCaseInsensitiveContains(query) }
        return Array(matching.dropFirst(min(max(skip ?? 0, 0), 10_000)).prefix(100).map(\.meta))
    }
    private static func parseEpisodes(_ data: Data, config: NTVIPTVConfiguration, base: MetaItem) throws -> Record {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StremioAPIError.invalidResponse }
        let bySeason = object["episodes"] as? [String: [[String: Any]]]
        let flat = object["episodes"] as? [[String: Any]]
        guard bySeason != nil || flat != nil else { throw StremioAPIError.invalidResponse }
        let pairs = bySeason?.flatMap { season, rows in rows.map { (Int(season), $0) } } ?? (flat ?? []).map { (nil as Int?, $0) }
        guard pairs.count <= 2000 else { throw StremioAPIError.responseTooLarge }
        var streams: [String: Stream] = [:], videos: [MetaVideo] = []
        for (fallbackSeason, row) in pairs {
            guard let number = string(row["id"]), NTVIPTVConfiguration.providerID(number),
                  let episode = string(row["episode_num"]).flatMap(Int.init), episode > 0,
                  let season = string(row["season"]).flatMap(Int.init) ?? fallbackSeason, season >= 0,
                  let url = config.mediaURL(section: .series, id: number, ext: string(row["container_extension"]) ?? "mp4") else { continue }
            let id = base.id + ".episode." + number
            guard streams[id] == nil else { continue }
            let info = row["info"] as? [String: Any] ?? [:]
            let title = string(row["title"]) ?? "Épisode \(episode)"
            videos.append(MetaVideo(id: id, title: title, season: season, episode: episode,
                thumbnail: artwork(info["movie_image"]), overview: string(info["plot"]), released: string(info["releasedate"])))
            streams[id] = Stream(name: "IPTV", title: title, description: nil, url: url, infoHash: nil, behaviorHints: nil)
        }
        let meta = withVideos(videos.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }, in: base)
        return Record(meta: meta, streams: streams)
    }
    private func record(config: NTVIPTVConfiguration, type: String, id: String) async throws -> Record {
        guard id.hasPrefix(config.prefix), let section = NTVIPTVSection(rawValue: type), config.destinations.contains(section) else {
            throw StremioAPIError.invalidResponse
        }
        scope(config)
        if let detail = detailCache[id], Date().timeIntervalSince(detail.loadedAt) < 300 { return detail.record }
        let list = try await records(config, section: section)
        guard let record = list.first(where: { $0.meta.id == id || $0.streams[id] != nil || id.hasPrefix($0.meta.id + ".episode.") }) else {
            throw StremioAPIError.emptyBody
        }
        guard section == .series, config.isXtream else { return record }
        if let cached = detailCache[record.meta.id], Date().timeIntervalSince(cached.loadedAt) < 300 { return cached.record }
        let number = String(record.meta.id.dropFirst((config.prefix + "series.").count))
        let data = try await load(config.apiURL(action: "get_series_info", seriesID: number))
        let detail = try Self.parseEpisodes(data, config: config, base: record.meta)
        try Task.checkCancellation()
        guard activeIdentity == config.identity else { throw CancellationError() }
        detailCache[record.meta.id] = (detail, Date())
        detailOrder.removeAll { $0 == record.meta.id }; detailOrder.append(record.meta.id)
        while detailOrder.count > 8 { detailCache.removeValue(forKey: detailOrder.removeFirst()) }
        return detail
    }
    func meta(config: NTVIPTVConfiguration, type: String, id: String) async throws -> MetaItem {
        try await record(config: config, type: type, id: id).meta
    }
    func streams(config: NTVIPTVConfiguration, type: String, id: String) async throws -> [Stream] {
        let record = try await record(config: config, type: type, id: id)
        return record.streams[id].map { [$0] } ?? []
    }
}
