#if DEBUG
import Foundation

/// Deterministic public metadata for the remote-navigation test only.
/// No account, private source, availability claim or playback URL is seeded.
enum NTVAnimeFixture {
    static func feed(for request: NTVAnimeRequest) -> NTVAnimeFeed {
        let examples: [(Int, String, String)] = [
            (195516, "Kusuriya no Hitorigoto 3rd Season", "bx195516-MJpUZlOberqH.jpg"),
            (195604, "Black Clover 2nd Season", "bx195604-tSZcfKbVqSEG.jpg"),
            (195539, "Cyberpunk: Edgerunners 2", "bx195539-t0GQQ9J9qtBW.jpg"),
            (159042, "Tensei Shitara Ken Deshita 2nd Season", "bx159042-GGFwlDskc5vR.png"),
            (189123, "Ao no Hako Season 2", "bx189123-0secXELIhkIW.jpg"),
            (160275, "Made in Abyss: Mezameru Shinpi", "bx160275-cBOWJpcCGeMq.jpg")
        ]
        let entries = examples.enumerated().map { index, example in
            let media = NTVAnimeMedia(id: example.0,
                title: .init(romaji: example.1, english: nil, native: nil),
                coverImage: .init(large: "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/" + example.2),
                bannerImage: index == 0 ? "https://s4.anilist.co/file/anilistcdn/media/anime/banner/195516-B5M0cPaQbQXI.jpg" : nil,
                description: "Fiche de démonstration du parcours Animés. La disponibilité se vérifie dans les addons.",
                episodes: nil, format: "TV", isAdult: false)
            switch request {
            case .season:
                return NTVAnimeEntry(id: "media.\(media.id)", media: media, episode: nil, airingAt: nil)
            case let .day(start, _):
                return NTVAnimeEntry(id: "airing.\(media.id)", media: media, episode: index + 2,
                    airingAt: Date(timeIntervalSince1970: Double(start + (12 + index) * 3600)))
            }
        }
        return NTVAnimeFeed(entries: entries, hasMore: false)
    }
}
#endif
