import XCTest
@testable import OrivioTV

extension NTVAnimeTests {
    private func playbackMedia(_ format: String = "TV") throws -> NTVAnimeMedia {
        try JSONDecoder().decode(NTVAnimeMedia.self, from: Data("{\"id\":1,\"title\":{\"romaji\":\"Titre test\"},\"format\":\"\(format)\",\"isAdult\":false}".utf8))
    }
    private func addon(types: [String], prefixes: [String], enabled: Bool = true) -> InstalledAddon {
        InstalledAddon(manifestURL: "https://example.invalid/manifest.json",
            manifest: AddonManifest(id: "fixture", name: "Fixture", version: "1", description: nil,
                logo: nil, types: types, idPrefixes: nil, catalogs: nil,
                resources: [.detailed(name: "meta", types: types, idPrefixes: prefixes)]), enabled: enabled)
    }

    func testExactIMDbMappingOpensTheSharedDetailWithoutInventingEpisodes() throws {
        let item = try NTVAnimePlaybackResolver.item(from: Data(#"{"anilist":1,"imdb":"tt0213338","kitsu":1,"media":"TV","themoviedb-season":3}"#.utf8),
            media: playbackMedia(), addons: [addon(types: ["series"], prefixes: ["tt"])])
        XCTAssertEqual(item?.id, "tt0213338")
        XCTAssertEqual(item?.type, "series")
        XCTAssertNil(item?.videos, "The shared detail must load real episode IDs, never invent season/episode numbers.")
        XCTAssertTrue(item.map(NTVAnimeDomain.contains) ?? false)
    }

    func testMovieAndKitsuRoutesRespectEnabledMetadataResourceCapabilities() throws {
        let data = Data(#"{"anilist":1,"imdb":"tt0213338","kitsu":42,"media":"MOVIE"}"#.utf8)
        XCTAssertEqual(try NTVAnimePlaybackResolver.item(from: data, media: playbackMedia("MOVIE"),
            addons: [addon(types: ["movie"], prefixes: ["tt"])])?.type, "movie")
        let series = Data(#"{"anilist":1,"imdb":"tt0213338","kitsu":42,"media":"TV"}"#.utf8)
        let item = try NTVAnimePlaybackResolver.item(from: series, media: playbackMedia(),
            addons: [addon(types: ["series"], prefixes: ["tt"], enabled: false), addon(types: ["anime"], prefixes: ["kitsu:"])])
        XCTAssertEqual(item?.id, "kitsu:42")
        XCTAssertEqual(item?.type, "anime")
        XCTAssertNil(try NTVAnimePlaybackResolver.item(from: data, media: playbackMedia("MOVIE"), addons: [addon(types: ["series"], prefixes: ["tt"])]))
    }

    func testUnmappedMismatchedAndMalformedIDsFallBackWithoutTitleGuessing() throws {
        for json in [#"{"anilist":2,"imdb":"tt0213338","media":"TV"}"#,
                     #"{"anilist":1,"imdb":"tt1:1:2","kitsu":-1,"media":"TV"}"#,
                     #"{"anilist":1,"imdb":null,"kitsu":null,"media":"TV"}"#,
                     #"{"anilist":1,"imdb":"tt0213338","media":"UNKNOWN"}"#] {
            XCTAssertNil(try NTVAnimePlaybackResolver.item(from: Data(json.utf8), media: playbackMedia(),
                addons: [addon(types: ["series"], prefixes: ["tt"])]))
        }
        XCTAssertNil(try NTVAnimePlaybackResolver.item(from: Data(#"{"anilist":1,"imdb":"tt0213338","media":"TV"}"#.utf8), media: playbackMedia(), addons: []))
        XCTAssertNil(try NTVAnimePlaybackResolver.item(from: Data(repeating: 32, count: (16 << 10) + 1),
            media: playbackMedia(), addons: [addon(types: ["series"], prefixes: ["tt"])]))
        XCTAssertThrowsError(try NTVAnimePlaybackResolver.item(from: Data("invalid".utf8),
            media: playbackMedia(), addons: [addon(types: ["series"], prefixes: ["tt"])]))
    }

    func testLookupUsesOnlyThePublicAniListIDAndPropagatesCancellation() async throws {
        let value = try playbackMedia()
        let addons = [addon(types: ["series"], prefixes: ["tt"])]
        let item = try await NTVAnimePlaybackResolver.resolve(value, addons: addons) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://arm.haglund.dev/api/v2/ids?source=anilist&id=1")
            XCTAssertLessThanOrEqual(request.timeoutInterval, 8)
            return Data(#"{"anilist":1,"imdb":"tt0213338","media":"TV"}"#.utf8)
        }
        XCTAssertEqual(item?.id, "tt0213338")
        do {
            _ = try await NTVAnimePlaybackResolver.resolve(value, addons: addons) { _ in throw CancellationError() }
            XCTFail("A cancelled lookup must not navigate to a fallback detail.")
        } catch is CancellationError {} catch { XCTFail("Unexpected error type") }
    }
}
