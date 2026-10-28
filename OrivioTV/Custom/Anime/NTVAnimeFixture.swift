#if DEBUG
import Foundation

/// Deterministic public metadata for the remote-navigation test only.
/// No account, private source, availability claim or playback URL is seeded.
enum NTVAnimeFixture {
    static var directPlayback: Bool { ProcessInfo.processInfo.arguments.contains("-ntvAnimeDirectFixture") }
    static let addon = InstalledAddon(manifestURL: "https://example.invalid/ntv-anime-fixture/manifest.json",
        manifest: AddonManifest(id: "ntv-anime-fixture", name: "Sources de test", version: "1", description: nil,
            logo: nil, types: ["movie", "series"], idPrefixes: ["tt999999"], catalogs: nil,
            resources: [.simple("meta"), .simple("stream")]))
    static func mapping(for media: NTVAnimeMedia) -> Data {
        let movie = media.format == "MOVIE"
        return Data("{\"anilist\":\(media.id),\"imdb\":\"tt999999\(movie ? 2 : 1)\",\"media\":\"\(movie ? "MOVIE" : "TV")\"}".utf8)
    }
    static func meta(id: String) -> MetaItem? {
        guard directPlayback, ["tt9999991", "tt9999992"].contains(id) else { return nil }
        let movie = id == "tt9999992"
        return MetaItem(id: id, type: movie ? "movie" : "series", name: movie ? "Film de test" : "Série de test",
            description: "Validation du parcours direct Animés.", genres: ["Anime"],
            videos: movie ? nil : [MetaVideo(id: id + ":3:7", title: "Épisode de test", season: 3, episode: 7)])
    }
    static func streams(id: String) -> [Stream]? {
        guard directPlayback, ["tt9999991:3:7", "tt9999992"].contains(id) else { return nil }
        return [Stream(name: "Source de test", title: id == "tt9999992" ? "Film de test · 1080p" : "Épisode 3.7 de test · 1080p",
            description: nil, url: "https://example.invalid/ntv-anime-fixture.mp4", infoHash: nil, behaviorHints: nil)]
    }
    static func feed(for request: NTVAnimeRequest, page: Int = 1) -> NTVAnimeFeed {
        let examples: [(Int, String, String)] = [
            (195516, "Kusuriya no Hitorigoto 3rd Season", "bx195516-MJpUZlOberqH.jpg"),
            (195604, "Black Clover 2nd Season", "bx195604-tSZcfKbVqSEG.jpg"),
            (195539, "Cyberpunk: Edgerunners 2", "bx195539-t0GQQ9J9qtBW.jpg"),
            (159042, "Tensei Shitara Ken Deshita 2nd Season", "bx159042-GGFwlDskc5vR.png"),
            (189123, "Ao no Hako Season 2", "bx189123-0secXELIhkIW.jpg"),
            (160275, "Made in Abyss: Mezameru Shinpi", "bx160275-cBOWJpcCGeMq.jpg")
        ]
        let entries = examples.enumerated().map { index, example in
            let media = NTVAnimeMedia(id: example.0 + (page - 1) * 1_000_000,
                title: .init(romaji: example.1, english: nil, native: nil),
                coverImage: .init(
                    large: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/" + example.2,
                    extraLarge: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/" + example.2),
                bannerImage: index == 0 ? "https://s4.anilist.co/file/anilistcdn/media/anime/banner/195516-B5M0cPaQbQXI.jpg" : nil,
                description: "Fiche de démonstration du parcours Animés. La disponibilité se vérifie dans les addons.",
                episodes: nil, format: directPlayback && index == 1 ? "MOVIE" : "TV", isAdult: false)
            switch request {
            case .season:
                return NTVAnimeEntry(id: "media.\(media.id)", media: media, episode: nil, airingAt: nil)
            case let .day(start, _):
                return NTVAnimeEntry(id: "airing.\(media.id)", media: media, episode: index + 2,
                    airingAt: Date(timeIntervalSince1970: Double(start + (12 + index) * 3600)))
            }
        }
        return NTVAnimeFeed(entries: entries, hasMore: page == 1)
    }
}
#endif
