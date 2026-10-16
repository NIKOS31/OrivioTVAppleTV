import XCTest
@testable import OrivioTV

final class NTVAnimeTests: XCTestCase {
    func testAnimeDomainUsesExplicitProviderHintsInsteadOfAnimationOrTitleGuessing() {
        XCTAssertTrue(NTVAnimeDomain.contains(MetaItem(id: "fixture", type: "anime", name: "Titre")))
        XCTAssertTrue(NTVAnimeDomain.contains(MetaItem(id: "kitsu:123", type: "series", name: "Titre")))
        XCTAssertTrue(NTVAnimeDomain.contains(MetaItem(id: "fixture", type: "movie", name: "Titre", genres: ["Animés", "Action"])))
        XCTAssertTrue(NTVAnimeDomain.contains(MetaItem(id: "fixture", type: "series", name: "Titre", genres: ["Japanese Animation"])))
        XCTAssertFalse(NTVAnimeDomain.contains(MetaItem(id: "fixture", type: "movie", name: "Film d’animation", genres: ["Animation", "Family"])))
        XCTAssertFalse(NTVAnimeDomain.contains(MetaItem(id: "fixture", type: "movie", name: "Anime dans le titre", genres: ["Documentary"])))
        XCTAssertTrue(MetaItem(id: "kitsu:123", type: "anime", name: "Série").isSeries)
        XCTAssertFalse(MetaItem(id: "fixture", type: "movie", name: "Film", genres: ["Anime"]).isSeries)
    }

    @MainActor
    func testSearchStateDoesNotCarryResultsAcrossProfiles() {
        let model = SearchViewModel(includesAnime: true)
        model.query = "Ancienne recherche"
        model.results = [MetaItem(id: "fixture", type: "anime", name: "Titre du profil précédent")]
        model.trending = model.results
        model.resetForProfile()
        XCTAssertTrue(model.query.isEmpty)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.trending.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    @MainActor
    func testAnimeRecognitionPersistsPerProfileAndKeepsMovieAndSeriesIDsDistinct() throws {
        let suite = "ntv.anime.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sparse = MetaItem(id: "tmdb:123", type: "series", name: "Titre")
        let store = NTVAnimeLibrary(defaults: defaults)
        XCTAssertFalse(store.contains(sparse, profile: 1))
        store.remember(sparse, profile: 1)
        store.remember(sparse, profile: 1)
        XCTAssertEqual(store.revision, 1, "A duplicate selection must not republish the library.")
        XCTAssertTrue(store.contains(MetaItem(id: "tmdb:123", type: "tv", name: "Autre nom"), profile: 1))
        XCTAssertFalse(store.contains(MetaItem(id: "tmdb:123", type: "movie", name: "Film"), profile: 1))
        XCTAssertFalse(store.contains(sparse, profile: 2))
        XCTAssertTrue(NTVAnimeLibrary(defaults: defaults).contains(sparse, profile: 1))
        XCTAssertTrue(store.contains(MetaItem(id: "simkl_upnext_tmdb:123_S1E2", type: "series", name: "Épisode"), profile: 1))
        XCTAssertFalse(String(describing: defaults.dictionaryRepresentation()).contains("Autre nom"), "Persist identifiers only, not metadata or URLs.")
        XCTAssertFalse(String(describing: defaults.dictionaryRepresentation()).contains("tmdb:123"), "Persist opaque digests rather than raw addon identifiers.")
        store.forget(sparse, profile: 2)
        XCTAssertTrue(store.contains(sparse, profile: 1), "A different profile cannot undo this profile’s classification.")
        store.forget(sparse, profile: 1)
        XCTAssertFalse(NTVAnimeLibrary(defaults: defaults).contains(sparse, profile: 1))
    }

    @MainActor
    func testGeneralCatalogDoesNotOfferAnExplicitAnimeShelf() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["series"],"resources":["catalog"],"catalogs":[{"type":"series","id":"all","name":"Populaires"},{"type":"series","id":"anime-top","name":"Animés"},{"type":"series","id":"animation","name":"Animation"}]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        let model = NTVCatalogBrowserModel()
        model.configure(addons: [addon], type: "series", scope: "fixture")
        XCTAssertEqual(model.sources.map(\.catalog.id), ["all", "animation"])
    }

    @MainActor
    func testFilteringAnimeDoesNotRepeatTheFirstPageOrHideLaterMovies() async throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["movie"],"resources":["catalog"],"catalogs":[{"type":"movie","id":"all"}]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        var offsets: [Int] = []
        let model = CatalogSeeAllViewModel(addon: addon, catalog: manifest.catalogs![0], fetch: { offset in
            offsets.append(offset)
            if offset == 0 { return [MetaItem(id: "fixture.anime", type: "movie", name: "Animé", genres: ["Anime"])] }
            if offset == 1 { return [MetaItem(id: "fixture.movie", type: "movie", name: "Film")] }
            return []
        })
        await model.loadMore()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.reachedEnd)
        XCTAssertTrue(model.needsPageAdvance)
        await model.loadMore()
        XCTAssertEqual(offsets, [0, 1])
        XCTAssertEqual(model.items.map(\.id), ["fixture.movie"])
        XCTAssertFalse(model.needsPageAdvance)
        await model.loadMore()
        XCTAssertTrue(model.reachedEnd)
    }

    func testAnimePresentationUsesFrenchSeasonAndFormatLabels() throws {
        XCTAssertEqual(NTVAnimeRequest.season(year: 2026, name: "FALL").seasonLabel, "Automne 2026")
        XCTAssertNil(NTVAnimeRequest.day(start: 1, end: 2).seasonLabel)
        let data = Data(#"{"id":1,"title":{"romaji":"Titre"},"isAdult":false,"format":"MOVIE"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(NTVAnimeMedia.self, from: data).formatLabel, "Film")
    }

    private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        return value
    }
    private func media(_ id: Int = 1, adult: String = "false", image: String = "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/test.jpg") -> String {
        "{\"id\":\(id),\"title\":{\"romaji\":\"Animé de test\"},\"isAdult\":\(adult),\"coverImage\":{\"large\":\"\(image)\"}}"
    }
    func testCalendarDaysUseRealLocalMidnightsThroughBothDSTChanges() {
        let calendar = calendar()
        for (month, expectedHours) in [(3, 23.0), (10, 25.0)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 29 : 25, hour: 12))!
            let days = NTVAnimeDay.week(containing: date, calendar: calendar)
            XCTAssertEqual(days.count, 7)
            XCTAssertEqual(calendar.component(.weekday, from: days[0].start), 2)
            let current = days.first { $0.contains(date) }!
            XCTAssertEqual(current.end.timeIntervalSince(current.start) / 3600, expectedHours)
            XCTAssertTrue(current.contains(current.start))
            XCTAssertFalse(current.contains(current.end))
            for index in 1..<days.count { XCTAssertEqual(days[index - 1].end, days[index].start) }
        }
    }
    func testSeasonBoundaryDoesNotDependOnElapsedDaySeconds() {
        let calendar = calendar()
        for (month, season) in [(1, "WINTER"), (4, "SPRING"), (7, "SUMMER"), (10, "FALL")] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: 1))!
            XCTAssertEqual(NTVAnimeRequest.season(at: date, calendar: calendar), .season(year: 2026, name: season))
        }
    }
    func testSeasonRejectsAdultOrUnspecifiedRatingAndDeduplicatesMedia() throws {
        let json = "{\"data\":{\"Page\":{\"media\":[\(media()),\(media()),\(media(2, adult: "true")),\(media(3, adult: "null"))]}}}"
        let feed = try NTVAnimeService.decode(Data(json.utf8), for: .season(year: 2026, name: "FALL"))
        XCTAssertEqual(feed.entries.map(\.media.id), [1])
    }
    func testScheduleKeepsOnlyTheSelectedHalfOpenDayAndSortsAirings() throws {
        let request = NTVAnimeRequest.day(start: 100_000, end: 186_400)
        func airing(_ id: Int, _ time: Int) -> String {
            "{\"id\":\(id),\"episode\":2,\"airingAt\":\(time),\"media\":\(media())}"
        }
        let json = "{\"data\":{\"Page\":{\"pageInfo\":{\"hasNextPage\":true},\"airingSchedules\":[\(airing(1, 186_399)),\(airing(2, 100_000)),\(airing(3, 186_400)),\(airing(4, 99_999)),\(airing(2, 100_000))]}}}"
        let feed = try NTVAnimeService.decode(Data(json.utf8), for: request)
        XCTAssertEqual(feed.entries.map(\.id), ["airing.2", "airing.1"])
        XCTAssertTrue(feed.hasMore)
    }
    func testGraphQLErrorsAndOversizedOrExcessivePagesAreNotPresentedAsEmptySuccess() throws {
        let request = NTVAnimeRequest.season(year: 2026, name: "FALL")
        XCTAssertThrowsError(try NTVAnimeService.decode(Data("{\"data\":{\"Page\":{\"media\":[]}},\"errors\":[{\"message\":\"private remote error\"}]}".utf8), for: request))
        XCTAssertThrowsError(try NTVAnimeService.decode(Data(repeating: 32, count: (1 << 20) + 1), for: request))
        let many = (1...25).map { media($0) }.joined(separator: ",")
        XCTAssertThrowsError(try NTVAnimeService.decode(Data("{\"data\":{\"Page\":{\"media\":[\(many)]}}}".utf8), for: request))
    }
    func testArtworkCannotUseLocalHostsCredentialsOrNonHTTPS() throws {
        for image in ["http://s4.anilist.co/file/anilistcdn/media/a.jpg", "https://127.0.0.1/file/anilistcdn/media/a.jpg", "https://secret@s4.anilist.co/file/anilistcdn/media/a.jpg", "file:///private/a.jpg", "https://s4.anilist.co/file/anilistcdn/media/a.jpg?redirect=http://127.0.0.1"] {
            let item = try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(media(image: image).utf8))
            XCTAssertNil(item.artwork)
        }
        XCTAssertNotNil(try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(media().utf8)).artwork)
        let ordinary = "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/test.jpg"
        let larger = "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/test.jpg"
        func cover(_ extra: String?) throws -> NTVAnimeMedia {
            let images: [String: Any] = ["large": ordinary, "extraLarge": extra.map { $0 as Any } ?? NSNull()]
            let object: [String: Any] = ["id": 1, "title": ["romaji": "Test"], "coverImage": images]
            return try JSONDecoder().decode(NTVAnimeMedia.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(try cover(larger).artwork, larger)
        XCTAssertEqual(try cover(nil).artwork, ordinary)
        XCTAssertEqual(try cover("https://127.0.0.1/private.jpg").artwork, ordinary)
    }
    func testCalendarQueryUsesBoundedVariablesAndDoesNotEmbedSearchText() throws {
        let data = try NTVAnimeService.payload(for: .day(start: 100_000, end: 186_400))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue((payload["query"] as? String)?.contains("coverImage { extraLarge large }") == true)
        let variables = try XCTUnwrap(payload["variables"] as? [String: Int])
        XCTAssertEqual(variables["from"], 99_999)
        XCTAssertEqual(variables["to"], 186_400)
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .day(start: 20, end: 10)))
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .day(start: 20, end: Int.max)))
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .season(year: 2026, name: "FALL) { other }")))
    }
    func testRateLimitStopsSubsequentRequestsWithoutExposingResponseBody() async throws {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let client = NTVAnimeService { request in
            await counter.increment()
            XCTAssertEqual(request.url?.absoluteString, "https://graphql.anilist.co")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "nan"])!
            return (Data("untrusted body".utf8), response)
        }
        for _ in 0..<2 {
            do { _ = try await client.load(.season(year: 2026, name: "FALL")); XCTFail("Expected backoff") }
            catch { XCTAssertEqual(error as? NTVAnimeError, .limited) }
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testSummaryRemainsBoundedPlainTextInsteadOfHTML() throws {
        let json = "{\"id\":1,\"title\":{\"romaji\":\"Test\"},\"description\":\"<i>Un titre</i><br><br/>Texte &amp; suite\",\"isAdult\":false}"
        let item = try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(json.utf8))
        XCTAssertFalse(item.summary.contains("<"))
        XCTAssertTrue(item.summary.contains("Texte & suite"))
        XCTAssertTrue(item.summary.contains("\n"))
        let long = "{\"id\":1,\"title\":{\"romaji\":\"Test\"},\"description\":\"" + String(repeating: "a", count: 8000) + "\"}"
        XCTAssertEqual(try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(long.utf8)).summary.count, 2000)
    }

    func testPublicMetadataIsReusedWithoutSendingAnAccountOrAddon() async throws {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let body = Data("{\"data\":{\"Page\":{\"media\":[]}}}".utf8)
        let client = NTVAnimeService { request in
            await counter.increment()
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (body, response)
        }
        let request = NTVAnimeRequest.season(year: 2026, name: "FALL")
        _ = try await client.load(request)
        _ = try await client.load(request)
        let count = await counter.count
        XCTAssertEqual(count, 1, "Returning to the same season must use its short-lived cache.")
    }
}
