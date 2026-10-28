import XCTest
@testable import OrivioTV

final class NTVDetailMetadataTests: XCTestCase {
    private let addonURL = URL(string: "https://metadata.example.invalid/meta/movie/fixture.json")!

    private func meta(_ object: [String: Any]) throws -> MetaItem {
        let body = try JSONSerialization.data(withJSONObject: ["meta": object])
        let checked = try NTVAddonPayloadPolicy.checkedData(body, resource: .meta, source: addonURL)
        return try XCTUnwrap(JSONDecoder().decode(MetaResponse.self, from: checked).meta)
    }

    private func configuredTMDB() -> TMDBSettings {
        var settings = TMDBSettings()
        settings.enabled = true
        settings.apiKey = "fixture-only"
        return settings
    }

    func testAddonPortraitsDecodeWithoutReplacingNamesOrGuessingPersonIDs() throws {
        let item = try meta([
            "id": "fixture", "type": "movie", "name": "Film", "cast": ["Personne A", "Personne B"],
            "app_extras": ["cast": [
                ["name": "Personne A", "character": "Rôle A", "photo": "https://images.example.invalid/a.jpg", "tmdbId": 42],
                ["name": "Personne B", "photo": "https://images.example.invalid/b.jpg", "tvdbId": 42]
            ]]
        ])
        XCTAssertEqual(item.cast, ["Personne A", "Personne B"])
        XCTAssertEqual(item.castDetails?.map(\.name), item.cast)
        XCTAssertEqual(item.castDetails?.first?.profileURL, "https://images.example.invalid/a.jpg")
        XCTAssertEqual(item.castDetails?.first?.character, "Rôle A")
        XCTAssertEqual(item.castDetails?.first?.tmdbID, 42)
        XCTAssertNil(item.castDetails?.last?.tmdbID, "A TVDB identifier must never open a different TMDB person.")
    }

    func testMalformedAndDuplicatePeopleCannotDropTheMetadataOrDuplicateFocusIDs() throws {
        let item = try meta([
            "id": "fixture", "name": "Film",
            "app_extras": ["cast": [
                NSNull(), 7, ["name": "  "],
                ["name": " Personne A ", "tmdbId": "42"],
                ["name": "Alias", "tmdbId": 42],
                ["name": "Personne B", "tmdbId": -1],
                ["name": "Personne B", "tmdbId": 0],
                ["name": "Personne C", "tmdbId": "not-an-id"]
            ] as [Any]]
        ])
        let people = try XCTUnwrap(item.castDetails)
        XCTAssertEqual(people.map(\.name), ["Personne A", "Personne B", "Personne C"])
        XCTAssertEqual(people.map(\.tmdbID), [42, nil, nil])
        XCTAssertEqual(Set(people.map(\.id)).count, people.count)
    }

    func testAddonPortraitLinksUseTheExistingSecondaryLinkPolicy() throws {
        let people = ["file:///private/image.jpg", "http://127.0.0.1/image.jpg", "https://images.example.invalid/safe.jpg"]
            .enumerated().map { ["name": "Personne \($0.offset)", "photo": $0.element] }
        let item = try meta(["id": "fixture", "name": "Film", "app_extras": ["cast": people]])
        XCTAssertEqual(item.castDetails?.count, 3, "Removing an unsafe optional photo must keep the person's name.")
        XCTAssertNil(item.castDetails?[0].profileURL)
        XCTAssertNil(item.castDetails?[1].profileURL)
        XCTAssertEqual(item.castDetails?[2].profileURL, "https://images.example.invalid/safe.jpg")
    }

    func testAddonPortraitCollectionIsBoundedBeforeLossyDecoding() throws {
        let people = Array(repeating: ["name": "Personne"], count: 257)
        XCTAssertThrowsError(try meta(["id": "fixture", "name": "Film", "app_extras": ["cast": people]]))
    }

    func testPortraitsSurviveCacheRoundTripIdentityAndPosterCopies() throws {
        let person = MetaCastMember(name: "Personne", character: nil, profileURL: "https://images.example.invalid/a.jpg", tmdbID: 42)
        let item = MetaItem(id: "fixture", type: "series", name: "Série", poster: "https://images.example.invalid/decorated.jpg",
            description: "Résumé fourni.", cast: [person.name], videos: [MetaVideo(id: "fixture:1:1", title: nil, season: 1, episode: 1)],
            posterFallback: "https://images.example.invalid/plain.jpg", released: "2026-01-01", castDetails: [person])
        let restored = try JSONDecoder().decode(MetaItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored, item)
        let copied = restored.withID("tt0000001").withPlainPoster()
        XCTAssertEqual(copied.castDetails, item.castDetails)
        XCTAssertEqual(copied.description, item.description)
        XCTAssertEqual(copied.videos, item.videos)
        XCTAssertEqual(copied.released, item.released)
        XCTAssertEqual(copied.poster, item.posterFallback)
    }

    @MainActor
    func testAddonPortraitsDisplayWithoutTMDBAndMissingPhotosKeepTheNameFallback() {
        let portrait = MetaCastMember(name: "Personne", character: nil, profileURL: "https://images.example.invalid/a.jpg", tmdbID: nil)
        let model = DetailViewModel(item: MetaItem(id: "fixture", type: "movie", name: "Film", castDetails: [portrait]))
        XCTAssertEqual(model.displayCast, [portrait])
        XCTAssertNil(model.displayCast.first?.tmdbID)
        let nameOnly = MetaCastMember(name: "Personne", character: nil, profileURL: nil, tmdbID: nil)
        model.meta = MetaItem(id: "fixture", type: "movie", name: "Film", castDetails: [nameOnly])
        XCTAssertTrue(model.displayCast.isEmpty)
        XCTAssertEqual(model.meta.castDetails?.map(\.name), ["Personne"])
    }

    @MainActor
    func testMissingTMDBPortraitUsesOnlyTheSameVerifiedPersonFromTheAddon() {
        let portrait = MetaCastMember(name: "Personne", character: nil, profileURL: "https://images.example.invalid/a.jpg", tmdbID: 42)
        let model = DetailViewModel(item: MetaItem(id: "fixture", type: "movie", name: "Film", castDetails: [portrait]))
        model.cast = [TMDBService.CastMember(id: 42, name: "Personne", character: "Rôle", profileURL: nil)]
        XCTAssertEqual(model.displayCast.first?.profileURL, portrait.profileURL)
        model.cast = [TMDBService.CastMember(id: 43, name: "Personne", character: nil, profileURL: nil)]
        XCTAssertNil(model.displayCast.first?.profileURL, "A matching name is insufficient evidence to reuse another person's face.")
    }

    @MainActor
    func testLocalizedOverviewReplacesAddonTextWithoutChangingIdentityArtworkOrEpisodes() async {
        let episode = MetaVideo(id: "tt0000001:1:1", title: nil, season: 1, episode: 1)
        let person = MetaCastMember(name: "Personne", character: nil, profileURL: "https://images.example.invalid/a.jpg", tmdbID: 42)
        let item = MetaItem(id: "tt0000001", type: "series", name: "Série", poster: "https://images.example.invalid/poster.jpg",
            background: "https://images.example.invalid/backdrop.jpg", logo: "https://images.example.invalid/logo.png",
            description: "Original addon text.", videos: [episode], castDetails: [person])
        let model = DetailViewModel(item: item)
        var detail = TMDBService.Detail()
        detail.overview = "  Résumé réellement fourni dans la langue choisie. \n"
        await model.apply(detail: detail, tmdb: configuredTMDB())
        var expected = item
        expected.description = "Résumé réellement fourni dans la langue choisie."
        XCTAssertEqual(model.meta, expected)
        XCTAssertEqual(model.openingBackground, item.background)
        XCTAssertEqual(model.openingLogo, item.logo)
        XCTAssertEqual(model.openingPoster, item.poster)
    }

    @MainActor
    func testMissingOrBlankLocalizedOverviewNeverErasesTheAddonSynopsis() async {
        let item = MetaItem(id: "fixture", type: "movie", name: "Film", description: "Résumé disponible.")
        for overview in [nil, "", " \n "] as [String?] {
            let model = DetailViewModel(item: item)
            var detail = TMDBService.Detail()
            detail.overview = overview
            await model.apply(detail: detail, tmdb: configuredTMDB())
            XCTAssertEqual(model.meta, item)
        }
    }

    @MainActor
    func testDetailAndCreditsPreferencesRemainIndependent() async {
        let item = MetaItem(id: "fixture", type: "movie", name: "Film", description: "Original addon text.")
        let model = DetailViewModel(item: item)
        var detail = TMDBService.Detail()
        detail.overview = "Résumé fourni."
        detail.cast = [TMDBService.CastMember(id: 42, name: "Personne", character: nil, profileURL: "https://images.example.invalid/a.jpg")]
        var settings = configuredTMDB()
        settings.useDetails = false
        await model.apply(detail: detail, tmdb: settings)
        XCTAssertEqual(model.meta, item)
        XCTAssertEqual(model.cast, detail.cast)
        settings.useDetails = true
        settings.useCredits = false
        let other = DetailViewModel(item: item)
        await other.apply(detail: detail, tmdb: settings)
        XCTAssertEqual(other.meta.description, detail.overview)
        XCTAssertTrue(other.cast.isEmpty)
    }

    @MainActor
    func testDisabledOrUnconfiguredTMDBCannotReplaceAddonMetadata() async {
        let item = MetaItem(id: "fixture", type: "movie", name: "Film", description: "Résumé addon.")
        var detail = TMDBService.Detail()
        detail.overview = "Autre résumé."
        detail.cast = [TMDBService.CastMember(id: 42, name: "Personne", character: nil, profileURL: nil)]
        var disabled = configuredTMDB()
        disabled.enabled = false
        var missingKey = configuredTMDB()
        missingKey.apiKey = " \n "
        for settings in [disabled, missingKey] {
            let model = DetailViewModel(item: item)
            await model.apply(detail: detail, tmdb: settings)
            XCTAssertEqual(model.meta, item)
            XCTAssertTrue(model.cast.isEmpty)
        }
    }
}
