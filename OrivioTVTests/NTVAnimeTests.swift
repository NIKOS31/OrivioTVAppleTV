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

    func testSeasonAndCalendarPaginationUseSeparateBoundedVariables() throws {
        for request in [NTVAnimeRequest.season(year: 1998, name: "SPRING"), .day(start: 100_000, end: 186_400)] {
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: NTVAnimeService.payload(for: request, page: 2)) as? [String: Any])
            let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
            XCTAssertEqual(variables["page"] as? Int, 2)
            XCTAssertTrue((payload["query"] as? String)?.contains("Page(page: $page") == true)
            for page in [0, -1, NTVAnimeService.maximumPages + 1, Int.max] {
                XCTAssertThrowsError(try NTVAnimeService.payload(for: request, page: page))
            }
        }
    }

    func testNavigatingCalendarWeeksPreservesWeekdayAcrossDST() throws {
        let calendar = calendar()
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let previous = NTVAnimeDay.shiftedWeek(from: sunday, by: -1, calendar: calendar)
        let next = NTVAnimeDay.shiftedWeek(from: sunday, by: 1, calendar: calendar)
        XCTAssertEqual(previous.count, 7)
        XCTAssertEqual(next.count, 7)
        XCTAssertEqual(calendar.component(.day, from: previous.last!.start), 22)
        XCTAssertEqual(calendar.component(.day, from: next.last!.start), 5)
        XCTAssertEqual(calendar.component(.weekday, from: next.first!.start), 2)
        XCTAssertTrue(NTVAnimeDay.shiftedWeek(from: sunday, by: Int.max, calendar: calendar).isEmpty)
    }

    @MainActor
    func testAnimePaginationKeepsStableOrderAndPagesWhenReturningFromDetail() async throws {
        actor Requests {
            var pages: [Int] = []
            func record(_ page: Int) { pages.append(page) }
        }
        let requests = Requests()
        let first = try entry(1), second = try entry(2), third = try entry(3)
        let model = NTVAnimeModel { _, page in
            await requests.record(page)
            return NTVAnimeFeed(entries: page == 1 ? [first, second] : [second, third], hasMore: page == 1)
        }
        let season = NTVAnimeRequest.season(year: 2004, name: "FALL")
        await model.load(season)
        await model.loadMore()
        XCTAssertEqual(model.feed.entries.map(\.id), [first.id, second.id, third.id])
        XCTAssertFalse(model.feed.hasMore)
        model.suspend()
        await model.load(season)
        let pages = await requests.pages
        XCTAssertEqual(pages, [1, 2], "Returning from a detail must not replace two pages with page one.")
        XCTAssertEqual(model.page, 2)
    }

    @MainActor
    func testAnimePaginationFailureRetainsCardsAndRetriesTheSamePage() async throws {
        actor Attempts {
            var pages: [Int] = []
            func record(_ page: Int) -> Bool {
                pages.append(page)
                return page == 2 && pages.filter { $0 == 2 }.count == 1
            }
        }
        let attempts = Attempts()
        let first = try entry(1), second = try entry(2)
        let model = NTVAnimeModel { _, page in
            if await attempts.record(page) { throw NTVAnimeError.limited }
            return NTVAnimeFeed(entries: [page == 1 ? first : second], hasMore: page == 1)
        }
        await model.load(.season(year: 2026, name: "FALL"))
        await model.loadMore()
        XCTAssertEqual(model.feed.entries.map(\.id), [first.id])
        XCTAssertEqual(model.page, 1)
        XCTAssertNotNil(model.snapshot.paginationError)
        XCTAssertFalse(model.snapshot.loadingMore)
        await model.loadMore()
        XCTAssertEqual(model.feed.entries.map(\.id), [first.id, second.id])
        XCTAssertNil(model.snapshot.paginationError)
        let pages = await attempts.pages
        XCTAssertEqual(pages, [1, 2, 2])
    }

    @MainActor
    func testFollowedCalendarFilterIncludesLaterPagesWithoutChangingThePublicFeed() async throws {
        let first = try entry(1), second = try entry(2)
        let model = NTVAnimeModel { _, page in
            NTVAnimeFeed(entries: [page == 1 ? first : second], hasMore: page == 1)
        }
        model.filterFollowing([second.media.id])
        await model.load(.day(start: 100_000, end: 186_400))
        XCTAssertTrue(model.snapshot.visibleEntries.isEmpty)
        XCTAssertTrue(model.feed.hasMore, "An empty personal page is not the end of the public schedule.")
        await model.loadMore()
        XCTAssertEqual(model.snapshot.visibleEntries.map(\.id), [second.id])
        XCTAssertEqual(model.feed.entries.count, 2)
        model.filterFollowing([])
        XCTAssertTrue(model.snapshot.visibleEntries.isEmpty)
        model.filterFollowing(nil)
        XCTAssertEqual(model.snapshot.visibleEntries.map(\.id), [first.id, second.id])
    }

    @MainActor
    func testLateAnimePageCannotReplaceTheNewSeason() async throws {
        let gate = NTVAnimeFeedGate()
        let oldEntry = try entry(1), newEntry = try entry(2)
        let model = NTVAnimeModel { request, _ in
            if request.seasonYear == 2001 { return await gate.wait() }
            return NTVAnimeFeed(entries: [newEntry], hasMore: false)
        }
        let old = Task { await model.load(.season(year: 2001, name: "FALL")) }
        try await until { await gate.started }
        await model.load(.season(year: 2026, name: "FALL"))
        await gate.release(NTVAnimeFeed(entries: [oldEntry], hasMore: false))
        await old.value
        XCTAssertEqual(model.feed.entries.map(\.id), [newEntry.id])
        XCTAssertFalse(model.loading)
    }

    @MainActor
    func testSuspendingAnimePaginationDiscardsItsLateReply() async throws {
        let gate = NTVAnimeFeedGate()
        let first = try entry(1), second = try entry(2)
        let model = NTVAnimeModel { _, page in
            if page == 2 { return await gate.wait() }
            return NTVAnimeFeed(entries: [first], hasMore: true)
        }
        let request = NTVAnimeRequest.season(year: 2026, name: "FALL")
        await model.load(request)
        let more = Task { await model.loadMore() }
        try await until { await gate.started }
        model.suspend()
        await gate.release(NTVAnimeFeed(entries: [second], hasMore: false))
        await more.value
        await model.load(request)
        XCTAssertEqual(model.feed.entries.map(\.id), [first.id])
        XCTAssertFalse(model.snapshot.loadingMore)
        XCTAssertEqual(model.page, 1)
    }

    @MainActor
    func testAnimeFollowsRemainLocalAndIsolatedBetweenProfiles() throws {
        let suite = "ntv.anime.follows.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NTVAnimeFollows(defaults: defaults)
        let item = try entry(1).media
        XCTAssertTrue(store.toggle(item, profile: 1))
        XCTAssertTrue(store.contains(1, profile: 1))
        XCTAssertFalse(store.contains(1, profile: 2))
        XCTAssertTrue(NTVAnimeFollows(defaults: defaults).contains(1, profile: 1))
        XCTAssertTrue(store.toggle(item, profile: 2))
        XCTAssertTrue(store.toggle(item, profile: 1))
        XCTAssertFalse(store.contains(1, profile: 1))
        XCTAssertTrue(store.contains(1, profile: 2))
    }

    @MainActor
    func testDeletingAProfilePurgesPersistedAndCachedAnimeFollows() throws {
        let suite = "ntv.anime.follows.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NTVAnimeFollows(defaults: defaults)
        XCTAssertTrue(store.toggle(try entry(1).media, profile: 2))
        XCTAssertTrue(store.toggle(try entry(2).media, profile: 3))
        XCTAssertEqual(store.ids(profile: 2), [1])
        store.forget(profile: 2)
        XCTAssertTrue(store.ids(profile: 2).isEmpty)
        XCTAssertTrue(NTVAnimeFollows(defaults: defaults).items(profile: 2).isEmpty)
        XCTAssertEqual(store.ids(profile: 3), [2])
    }

    @MainActor
    func testAnimeFollowsStripUntrustedArtworkAndBoundStoredMetadata() throws {
        let suite = "ntv.anime.follows.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = NTVAnimeMedia(id: 9, title: .init(romaji: String(repeating: "a", count: 1000), english: nil, native: nil),
            coverImage: .init(large: "http://127.0.0.1/private"), bannerImage: "file:///private/image.jpg",
            description: "<b>Résumé</b>", episodes: -3, format: "untrusted", isAdult: false)
        let store = NTVAnimeFollows(defaults: defaults)
        XCTAssertTrue(store.toggle(value, profile: 1))
        let restored = try XCTUnwrap(NTVAnimeFollows(defaults: defaults).items(profile: 1).first)
        XCTAssertEqual(restored.displayTitle.count, 160)
        XCTAssertNil(restored.coverImage?.large)
        XCTAssertNil(restored.bannerImage)
        XCTAssertEqual(restored.description, "Résumé")
        XCTAssertNil(restored.episodes)
        XCTAssertNil(restored.format)
        let stored = try XCTUnwrap(defaults.data(forKey: followsStorageName(profile: 1)))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("127.0.0.1"))
    }

    @MainActor
    func testAnimeFollowsRejectOverflowAndCorruptStorage() throws {
        let suite = "ntv.anime.follows.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let items = try (1...NTVAnimeFollows.limit).map { try entry($0).media }
        defaults.set(try JSONEncoder().encode(items), forKey: followsStorageName(profile: 1))
        let store = NTVAnimeFollows(defaults: defaults)
        XCTAssertFalse(store.toggle(try entry(201).media, profile: 1))
        XCTAssertTrue(store.toggle(items[0], profile: 1), "A full list must still allow removal.")
        XCTAssertTrue(store.toggle(try entry(201).media, profile: 1))
        // Writing >1 MiB to real tvOS defaults terminates the test host.
        let oversized = try XCTUnwrap(NTVAnimeOversizedDefaults(suiteName: suite))
        XCTAssertTrue(NTVAnimeFollows(defaults: oversized).items(profile: 2).isEmpty)
        defaults.set(Data("invalid JSON".utf8), forKey: followsStorageName(profile: 3))
        XCTAssertTrue(store.items(profile: 3).isEmpty)
    }

    func testAnimeLanguagesPreserveLegacySettingsUntilExplicitlyEnabled() throws {
        let legacy = try JSONDecoder().decode(PlayerSettings.self, from: Data(#"{"preferredAudioLanguage":"fr","preferredSubtitleLanguage":"en","subtitlesOnByDefault":false}"#.utf8))
        XCTAssertFalse(legacy.animeLanguages.enabled)
        XCTAssertEqual(legacy.resolvedForAnime(true).preferredAudioLanguage, "fr")
        var value = legacy
        value.animeLanguages.enabled = true
        let anime = value.resolvedForAnime(true)
        XCTAssertEqual(anime.preferredAudioLanguage, "ja")
        XCTAssertEqual(anime.preferredSubtitleLanguage, "fr")
        XCTAssertTrue(anime.subtitlesOnByDefault)
        XCTAssertEqual(value.resolvedForAnime(false).preferredAudioLanguage, "fr")
        XCTAssertFalse(value.subtitlesOnByDefault, "Resolving an anime must not mutate the stored global preferences.")
        XCTAssertEqual(anime.playerEngine, value.playerEngine)
        let restored = try JSONDecoder().decode(PlayerSettings.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.animeLanguages, value.animeLanguages)
    }

    func testAnimeLanguagesCanDisableSubtitlesAndRejectUnknownLanguageCodes() {
        var value = PlayerSettings.default
        value.animeLanguages.enabled = true
        value.animeLanguages.audio = "invalid-code"
        value.animeLanguages.subtitle = "invalid-code"
        value.animeLanguages.subtitlesEnabled = false
        value.subtitleSecondaryLanguage = "en"
        value.subtitlePreferForced = true
        let anime = value.resolvedForAnime(true)
        XCTAssertEqual(anime.preferredAudioLanguage, "ja")
        XCTAssertEqual(anime.preferredSubtitleLanguage, "fr")
        XCTAssertFalse(anime.subtitlesOnByDefault)
        XCTAssertTrue(anime.subtitleSecondaryLanguage.isEmpty)
        XCTAssertFalse(anime.subtitlePreferForced)
        XCTAssertEqual(value.subtitleSecondaryLanguage, "en")
    }

    @MainActor
    func testSearchDistinguishesNoSearchableCatalogFromEmptySuccess() async throws {
        let model = SearchViewModel(debounce: .zero) { _, _, _ in [] }
        defer { model.suspendSearch() }
        model.query = "film"
        model.search(targets: [])
        XCTAssertEqual(model.outcome, .noCatalogs)
        XCTAssertFalse(model.isSearching)
        model.search(targets: try searchTargets(1))
        try await until { !model.isSearching }
        XCTAssertEqual(model.outcome, .empty)
        XCTAssertFalse(model.outcome.canRetry)
    }

    @MainActor
    func testSearchDistinguishesTotalOutageFromHealthyEmptyResults() async throws {
        let model = SearchViewModel(debounce: .zero) { _, _, _ in throw NTVAnimeError.unavailable }
        defer { model.suspendSearch() }
        model.query = "film"
        model.search(targets: try searchTargets(2))
        try await until { !model.isSearching }
        XCTAssertEqual(model.outcome, .unavailable)
        XCTAssertTrue(model.outcome.canRetry)
        XCTAssertTrue(model.results.isEmpty)
    }

    @MainActor
    func testSearchRetainsHealthyResultsAndReportsPartialFailure() async throws {
        let model = SearchViewModel(debounce: .zero) { _, catalog, _ in
            if catalog.id == "1" { throw NTVAnimeError.unavailable }
            return [MetaItem(id: "movie", type: "movie", name: "Un film")]
        }
        defer { model.suspendSearch() }
        model.query = "film"
        model.search(targets: try searchTargets(2))
        try await until { !model.isSearching }
        XCTAssertEqual(model.outcome, .partial(failed: 1))
        XCTAssertEqual(model.results.map(\.id), ["movie"])
        XCTAssertNotNil(model.outcome.notice)
        XCTAssertTrue(model.outcome.canRetry)
    }

    @MainActor
    func testSearchPartialFailureWithNoMatchDoesNotClaimCompleteEmptySuccess() async throws {
        let model = SearchViewModel(debounce: .zero) { _, catalog, _ in
            if catalog.id == "1" { throw NTVAnimeError.unavailable }
            return []
        }
        defer { model.suspendSearch() }
        model.query = "film"
        model.search(targets: try searchTargets(2))
        try await until { !model.isSearching }
        XCTAssertEqual(model.outcome, .partial(failed: 1))
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.outcome.emptyTitle, "Recherche incomplète")
    }

    @MainActor
    func testProfileResetRejectsAnOldSearchResponseEvenIfTransportIgnoresCancellation() async throws {
        let gate = NTVAnimeFeedGate()
        let model = SearchViewModel(debounce: .zero) { _, _, _ in
            _ = await gate.wait()
            return [MetaItem(id: "old", type: "movie", name: "Ancien profil")]
        }
        defer { model.suspendSearch() }
        model.query = "film"
        model.search(targets: try searchTargets(1))
        try await until { await gate.started }
        model.resetForProfile()
        await gate.release(NTVAnimeFeed(entries: [], hasMore: false))
        // Let both the child transport and its cancelled parent finish.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.outcome, .idle)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.query.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    private func followsStorageName(profile: Int) -> String { "ntv.anime.follows.v1.p\(profile)" }
    private func entry(_ id: Int) throws -> NTVAnimeEntry {
        NTVAnimeEntry(id: "media.\(id)", media: try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(media(id).utf8)), episode: nil, airingAt: nil)
    }
    private func searchTargets(_ count: Int) throws -> [(InstalledAddon, ManifestCatalog)] {
        try (0..<count).map { index in
            let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data("{\"id\":\"fixture.\(index)\",\"name\":\"Fixture\",\"version\":\"1\",\"resources\":[\"meta\",\"catalog\"],\"types\":[\"movie\"],\"catalogs\":[{\"id\":\"\(index)\",\"type\":\"movie\",\"extraSupported\":[\"search\"]}]}".utf8))
            return (InstalledAddon(manifestURL: "https://example.invalid/fixture.\(index)/manifest.json", manifest: manifest), manifest.catalogs![0])
        }
    }
    @MainActor private func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for an offline model transition")
        throw NTVAnimeError.unavailable
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

private final class NTVAnimeOversizedDefaults: UserDefaults, @unchecked Sendable {
    override func data(forKey defaultName: String) -> Data? {
        Data(repeating: 32, count: (1 << 20) + 1)
    }
}

private actor NTVAnimeFeedGate {
    private var continuation: CheckedContinuation<NTVAnimeFeed, Never>?
    private(set) var started = false
    func wait() async -> NTVAnimeFeed {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ feed: NTVAnimeFeed) {
        continuation?.resume(returning: feed)
        continuation = nil
    }
}
