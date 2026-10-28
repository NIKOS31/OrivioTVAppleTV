import Foundation

/// AniList IDs are not stream IDs; ARM is also used by AnimeSkipService.
enum NTVAnimePlaybackResolver {
    private struct Mapping: Decodable {
        let anilist: Int
        let imdb: String?
        let kitsu: Int?
        let media: String?
    }

    static func resolve(_ media: NTVAnimeMedia, addons: [InstalledAddon],
                        load: (URLRequest) async throws -> Data = fetch) async throws -> MetaItem? {
        guard media.canDisplay, media.id <= Int(Int32.max) else { return nil }
        var request = URLRequest(url: URL(string: "https://arm.haglund.dev/api/v2/ids?source=anilist&id=\(media.id)")!)
        request.timeoutInterval = 8
        let data = try await load(request)
        try Task.checkCancellation()
        return try item(from: data, media: media, addons: addons)
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await NTVBoundedResponse.data(for: request, session: .shared, maximumBytes: 16 << 10)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    static func item(from data: Data, media: NTVAnimeMedia, addons: [InstalledAddon]) throws -> MetaItem? {
        guard data.count <= 16 << 10, media.canDisplay else { return nil }
        let mapping = try JSONDecoder().decode(Mapping.self, from: data)
        guard mapping.anilist == media.id, let kind = mapping.media,
              kind == "TV" || kind == "MOVIE" else { return nil }
        let type = kind == "MOVIE" ? "movie" : "series"
        var candidates: [(String, String)] = []
        if let imdb = mapping.imdb, imdb.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) != nil {
            candidates.append((imdb, type))
        }
        if let kitsu = mapping.kitsu, (1...Int(Int32.max)).contains(kitsu) {
            candidates.append(("kitsu:\(kitsu)", type))
            if type == "series" { candidates.append(("kitsu:\(kitsu)", "anime")) }
        }
        let playable = candidates.filter { id, type in
            addons.contains { supports($0, resource: "meta", id: id, type: type) }
        }
        let withStreamProvider = playable.first { id, type in
            addons.contains { supports($0, resource: "stream", id: id, type: type) }
        }
        guard let (id, contentType) = withStreamProvider ?? playable.first else { return nil }
        // The normal detail obtains episodes from the addon; calendar numbers
        // must never be treated as an IMDb season or an episode stream ID.
        return MetaItem(id: id, type: contentType, name: media.displayTitle,
            poster: media.artwork, background: media.backdrop, description: media.summary, genres: ["Anime"])
    }

    private static func supports(_ addon: InstalledAddon, resource name: String, id: String, type: String) -> Bool {
        guard addon.enabled else { return false }
        return (addon.manifest.resources ?? []).contains { resource in
            guard resource.name == name else { return false }
            let types: [String]?
            let prefixes: [String]?
            switch resource {
            case .simple:
                types = addon.manifest.types; prefixes = addon.manifest.idPrefixes
            case let .detailed(_, resourceTypes, resourcePrefixes):
                types = resourceTypes ?? addon.manifest.types
                prefixes = resourcePrefixes ?? addon.manifest.idPrefixes
            }
            return (types?.contains(type) ?? true)
                && (prefixes.map { $0.isEmpty || $0.contains { id.hasPrefix($0) } } ?? true)
        }
    }
}
