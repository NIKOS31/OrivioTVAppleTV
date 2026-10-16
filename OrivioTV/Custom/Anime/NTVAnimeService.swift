import Foundation

struct NTVAnimeMedia: Decodable, Identifiable, Sendable {
    struct Title: Decodable, Sendable { let romaji: String?; let english: String?; let native: String? }
    struct Cover: Decodable, Sendable { let large: String? }
    let id: Int
    let title: Title
    let coverImage: Cover?
    let bannerImage: String?
    let description: String?
    let episodes: Int?
    let format: String?
    let isAdult: Bool?

    var displayTitle: String {
        for value in [title.romaji, title.english, title.native] {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(160)) }
        }
        return "Animé"
    }
    var searchTitle: String { displayTitle }
    var summary: String {
        // AniList can retain inline tags even with asHtml:false. Treat these
        // as plain text; never instantiate an HTML renderer for metadata.
        let raw = String((description ?? "").prefix(4000))
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]{0,512}>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "’")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Aucun résumé disponible." : String(raw.prefix(2000))
    }
    var artwork: String? { Self.imageURL(coverImage?.large) }
    var backdrop: String? { Self.imageURL(bannerImage) }
    private static func imageURL(_ raw: String?) -> String? {
        guard let raw, raw.count <= 2048, let url = URL(string: raw),
              url.scheme == "https", url.host == "s4.anilist.co", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil, url.query == nil,
              url.path.hasPrefix("/file/anilistcdn/media/") else { return nil }
        return url.absoluteString
    }
    var canDisplay: Bool { id > 0 && isAdult == false && displayTitle != "Animé" }
}

struct NTVAnimeEntry: Identifiable, Sendable {
    let id: String
    let media: NTVAnimeMedia
    let episode: Int?
    let airingAt: Date?
}

struct NTVAnimeDay: Identifiable, Hashable, Sendable {
    let start: Date
    let end: Date
    var id: Int { Int(start.timeIntervalSince1970) }

    static func week(containing date: Date, calendar original: Calendar = .current) -> [Self] {
        var calendar = original
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: offset, to: week.start),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return Self(start: start, end: end)
        }
    }
    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

enum NTVAnimeRequest: Hashable, Sendable {
    case season(year: Int, name: String)
    case day(start: Int, end: Int)

    static func season(at date: Date, calendar: Calendar = .current) -> Self {
        let names = ["WINTER", "SPRING", "SUMMER", "FALL"]
        let month = min(max(calendar.component(.month, from: date), 1), 12)
        return .season(year: calendar.component(.year, from: date), name: names[(month - 1) / 3])
    }
    static func day(_ value: NTVAnimeDay) -> Self {
        .day(start: value.id, end: Int(value.end.timeIntervalSince1970))
    }
    var cacheKey: String {
        switch self {
        case let .season(year, name): return "season.\(year).\(name)"
        case let .day(start, end): return "day.\(start).\(end)"
        }
    }
}

struct NTVAnimeFeed: Sendable { let entries: [NTVAnimeEntry]; let hasMore: Bool }

enum NTVAnimeError: Error, Equatable { case unavailable, invalidResponse, limited }

/// Public metadata only. No account, addon URL, playback URL or token is sent.
/// One cancellable transfer at a time; small, short-lived memory cache only.
actor NTVAnimeService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let shared = NTVAnimeService()
    private let transport: Transport
    private let pool = NTVSharedWorkPool<NTVAnimeFeed>(limit: 1)
    private var cache: [NTVAnimeRequest: (Date, NTVAnimeFeed)] = [:]
    private var nextRequest = Date.distantPast
    private var blockedUntil = Date.distantPast

    init(transport: @escaping Transport = NTVAnimeService.send) { self.transport = transport }

    func load(_ request: NTVAnimeRequest) async throws -> NTVAnimeFeed {
        try Task.checkCancellation()
        if let (saved, feed) = cache[request], Date().timeIntervalSince(saved) < 600 { return feed }
        return try await pool.value(for: request.cacheKey) { try await self.perform(request) }
    }

    private func perform(_ selection: NTVAnimeRequest) async throws -> NTVAnimeFeed {
        guard Date() >= blockedUntil else { throw NTVAnimeError.limited }
        let delay = nextRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(min(delay, 2) * 1_000_000_000)) }
        try Task.checkCancellation()
        nextRequest = Date().addingTimeInterval(2)
        let payload = try Self.payload(for: selection)
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = payload
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if response.statusCode == 429 {
            let proposed = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            let retry = proposed.isFinite ? min(max(proposed, 2), 1800) : 60
            blockedUntil = Date().addingTimeInterval(retry)
            throw NTVAnimeError.limited
        }
        guard response.statusCode == 200 else { throw NTVAnimeError.unavailable }
        let feed = try Self.decode(data, for: selection)
        cache = cache.filter { Date().timeIntervalSince($0.value.0) < 600 }
        if cache.count >= 10, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache.removeValue(forKey: oldest) }
        cache[selection] = (Date(), feed)
        return feed
    }

    static func payload(for selection: NTVAnimeRequest) throws -> Data {
        let fields = "id title { romaji english native } coverImage { large } bannerImage description(asHtml: false) episodes format isAdult"
        let query: String
        let variables: [String: Any]
        switch selection {
        case let .season(year, name):
            guard (1900...2200).contains(year), ["WINTER", "SPRING", "SUMMER", "FALL"].contains(name) else { throw NTVAnimeError.invalidResponse }
            query = "query($year: Int!, $season: MediaSeason!) { Page(page: 1, perPage: 24) { pageInfo { hasNextPage } media(type: ANIME, seasonYear: $year, season: $season, isAdult: false, sort: POPULARITY_DESC) { \(fields) } } }"
            variables = ["year": year, "season": name]
        case let .day(start, end):
            guard start > 0, end > start, end <= Int(Int32.max), end - start <= 26 * 3600 else { throw NTVAnimeError.invalidResponse }
            // Strict GraphQL comparisons become a half-open calendar day.
            query = "query($from: Int!, $to: Int!) { Page(page: 1, perPage: 50) { pageInfo { hasNextPage } airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) { id episode airingAt media { \(fields) } } } }"
            variables = ["from": start - 1, "to": end]
        }
        return try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    }

    static func decode(_ data: Data, for selection: NTVAnimeRequest) throws -> NTVAnimeFeed {
        guard data.count <= 1 << 20 else { throw NTVAnimeError.invalidResponse }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.errors?.isEmpty != false, let page = envelope.data?.Page else { throw NTVAnimeError.invalidResponse }
        var seen = Set<String>()
        let entries: [NTVAnimeEntry]
        switch selection {
        case .season:
            guard let media = page.media, media.count <= 24 else { throw NTVAnimeError.invalidResponse }
            entries = media.compactMap { item in
                let id = "media.\(item.id)"
                guard item.canDisplay, seen.insert(id).inserted else { return nil }
                return NTVAnimeEntry(id: id, media: item, episode: nil, airingAt: nil)
            }
        case let .day(start, end):
            guard let schedules = page.airingSchedules, schedules.count <= 50 else { throw NTVAnimeError.invalidResponse }
            entries = schedules.compactMap { item in
                let id = "airing.\(item.id)"
                guard item.id > 0, item.episode > 0, item.airingAt >= start, item.airingAt < end,
                      let media = item.media, media.canDisplay, seen.insert(id).inserted else { return nil }
                return NTVAnimeEntry(id: id, media: media, episode: item.episode,
                                     airingAt: Date(timeIntervalSince1970: Double(item.airingAt)))
            }.sorted { ($0.airingAt ?? .distantPast) < ($1.airingAt ?? .distantPast) }
        }
        return NTVAnimeFeed(entries: entries, hasMore: page.pageInfo?.hasNextPage == true)
    }

    private struct Envelope: Decodable {
        struct Body: Decodable { let Page: PageBody? }
        let data: Body?
        let errors: [ErrorBody]?
    }
    private struct ErrorBody: Decodable { let message: String? }
    private struct PageBody: Decodable {
        struct Info: Decodable { let hasNextPage: Bool? }
        let pageInfo: Info?
        let media: [NTVAnimeMedia]?
        let airingSchedules: [Schedule]?
    }
    private struct Schedule: Decodable { let id: Int; let episode: Int; let airingAt: Int; let media: NTVAnimeMedia? }

    private static let session = NTVAuthenticatedSession.make(timeout: 15)
    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 1 << 20)
    }
}
