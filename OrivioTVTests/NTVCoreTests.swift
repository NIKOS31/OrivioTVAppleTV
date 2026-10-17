import XCTest
import UIKit
@testable import OrivioTV

final class NTVIPTVRoutingTests: XCTestCase {
    private func config(_ destinations: Set<NTVIPTVSection> = [.tv, .movie, .series],
                        playlist: String = "https://provider.example/get.php?username=demo&password=demo",
                        untyped: NTVIPTVSection = .tv) throws -> NTVIPTVConfiguration {
        try XCTUnwrap(NTVIPTVConfiguration(playlist: playlist, destinations: destinations, untyped: untyped))
    }

    func testCredentialsRequireTLSAndNeverEnterInternalAddonOrContentIDs() throws {
        for raw in ["http://provider.example/list.m3u", "file:///tmp/list.m3u", "https://user:pass@provider.example/list", "https://provider.example/list#secret"] {
            XCTAssertNil(NTVIPTVConfiguration(playlist: raw, destinations: [.movie], untyped: .movie))
        }
        let config = try config()
        let addon = try XCTUnwrap(config.catalogAddon)
        XCTAssertEqual(addon.manifestURL, "ntv-iptv://local")
        XCTAssertFalse(addon.manifestURL.contains("demo"))
        XCTAssertFalse(config.prefix.contains("demo"))
        XCTAssertEqual(Set(addon.manifest.catalogs?.map(\.type) ?? []), Set(["movie", "series"]))
        XCTAssertTrue(addon.handles(id: config.prefix + "movie.1"))
        XCTAssertNil(try self.config([.tv]).catalogAddon)
        XCTAssertNil(try self.config([]).catalogAddon)
    }

    func testProviderURLKeepsSubpathsAndEncodesCredentialsInQueryAndMediaSegments() throws {
        let url = try XCTUnwrap(LiveTVSettingsStore.providerPlaylistURL(server: "provider.example/service/", username: "u/+", password: "p +&/"))
        let config = try self.config(playlist: url)
        let api = try config.apiURL(action: "get_series_info", seriesID: "12")
        let query = try XCTUnwrap(URLComponents(url: api, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(api.path, "/service/player_api.php")
        XCTAssertEqual(query.first { $0.name == "username" }?.value, "u/+")
        XCTAssertEqual(query.first { $0.name == "password" }?.value, "p +&/")
        let media = try XCTUnwrap(config.mediaURL(section: .movie, id: "12", ext: "MKV"))
        XCTAssertTrue(media.hasSuffix("/movie/u%2F%2B/p%20%2B%26%2F/12.mkv"))
        XCTAssertNil(config.mediaURL(section: .movie, id: "../12", ext: "mkv"))
        XCTAssertNil(config.mediaURL(section: .movie, id: "12", ext: "mkv/../../"))
        XCTAssertNil(config.mediaURL(section: .tv, id: "12", ext: "ts"))
        XCTAssertThrowsError(try config.apiURL(action: "delete_user"))
        XCTAssertThrowsError(try config.apiURL(action: "get_series_info", seriesID: "١٢"))
        let endpoint = try XCTUnwrap(LiveTVSettingsStore.providerPlaylistURL(server: "https://provider.example/service/get.php", username: "demo", password: "demo"))
        XCTAssertEqual(URL(string: endpoint)?.path, "/service/get.php")
        XCTAssertNil(LiveTVSettingsStore.providerPlaylistURL(server: "http://provider.example", username: "demo", password: "demo"))
        XCTAssertNil(LiveTVSettingsStore.providerPlaylistURL(server: "https://provider.example/?token=x", username: "demo", password: "demo"))
    }

    func testM3UTypesAreExplicitOrPathBasedAndUntypedLinksHaveOneFallback() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 media-type="movie",Film
        https://provider.example/plain/1
        #EXTINF:-1 tvg-type="series",Show S01E01
        https://provider.example/plain/2
        #EXTINF:-1,Live
        https://provider.example/live/movie/demo/3.ts
        #EXTINF:-1,Unknown
        https://provider.example/plain/4
        """
        let channels = M3UService.parse(text)
        let config = try self.config(playlist: "https://provider.example/list.m3u", untyped: .movie)
        XCTAssertEqual(channels.count, 4)
        XCTAssertEqual(channels.map { config.section(for: $0) }, [.movie, .series, .tv, .movie])
        XCTAssertNil(channels[3].declaredSection, "The previous entry's declaration must not leak.")
    }

    func testXtreamMoviesAreSearchablePaginatedAndResolvedWithoutAnotherProvider() async throws {
        let rows = (0..<105).map { ["stream_id": String($0), "name": "Film \($0)", "container_extension": "mkv"] }
        let data = try JSONSerialization.data(withJSONObject: rows + [rows[0]])
        let config = try self.config()
        let service = NTVIPTVCatalogService { url in
            XCTAssertTrue(url.absoluteString.contains("action=get_vod_streams"))
            return data
        }
        let page = try await service.catalog(config: config, type: "movie", search: nil, skip: nil)
        let next = try await service.catalog(config: config, type: "movie", search: nil, skip: 100)
        let search = try await service.catalog(config: config, type: "movie", search: "Film 104", skip: nil)
        XCTAssertEqual(page.count, 100)
        XCTAssertEqual(next.count, 5)
        XCTAssertEqual(search.map(\.id), [config.prefix + "movie.104"])
        let streams = try await service.streams(config: config, type: "movie", id: search[0].id)
        XCTAssertEqual(streams.first?.url, "https://provider.example/movie/demo/demo/104.mkv")
    }

    func testDisabledDestinationMakesNoProviderRequest() async throws {
        let service = NTVIPTVCatalogService { _ in XCTFail("A disabled section must not fetch."); return Data() }
        let results = try await service.catalog(config: config([.tv]), type: "movie", search: nil, skip: nil)
        XCTAssertTrue(results.isEmpty)
    }

    func testXtreamEpisodesUseDeclaredSeasonAndEpisodeAndSortBeforePlayback() async throws {
        let list = Data(#"[{"series_id":7,"name":"Show","cover":"https://images.example/show.jpg"}]"#.utf8)
        let info = Data(#"{"episodes":{"2":[{"id":"72","episode_num":2,"title":"Second","container_extension":"mkv"},{"id":"71","episode_num":1,"title":"First","container_extension":"mp4"},{"id":"71","episode_num":1},{"id":"73","title":"No number"}]}}"#.utf8)
        let service = NTVIPTVCatalogService { url in url.query?.contains("get_series_info") == true ? info : list }
        let config = try config()
        let meta = try await service.meta(config: config, type: "series", id: config.prefix + "series.7")
        XCTAssertEqual(meta.videos?.map(\.episode), [1, 2])
        XCTAssertEqual(meta.videos?.map(\.season), [2, 2])
        let episode = try XCTUnwrap(meta.videos?.first)
        let streams = try await service.streams(config: config, type: "series", id: episode.id)
        XCTAssertEqual(streams.first?.url, "https://provider.example/series/demo/demo/71.mp4")
    }

    func testXtreamFlatEpisodeVariantKeepsOnlyUsableEntries() async throws {
        let list = Data(#"[{"series_id":"1","name":"Show"}]"#.utf8)
        let info = Data(#"{"episodes":[{"id":11,"season":1,"episode_num":1},{"id":12,"episode_num":2},{"id":13,"season":1,"episode_num":3,"container_extension":"exe"}]}"#.utf8)
        let service = NTVIPTVCatalogService { url in url.query?.contains("get_series_info") == true ? info : list }
        let config = try config()
        let meta = try await service.meta(config: config, type: "series", id: config.prefix + "series.1")
        XCTAssertEqual(meta.videos?.count, 1)
        XCTAssertEqual(meta.videos?.first?.episode, 1)
    }

    func testM3USeriesGroupOnlyExplicitEpisodeNumbersAndRetainPlaybackHeaders() async throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 media-type="series",Show S01E02
        https://provider.example/series/two.mkv
        #EXTINF:-1 media-type="series",Show S01E01
        #EXTVLCOPT:http-user-agent=nTV-test
        https://provider.example/series/one.mkv
        #EXTINF:-1 media-type="series",Show unknown
        https://provider.example/series/unknown.mkv
        #EXTINF:-1 media-type="series",Show S01E03
        http://provider.example/series/cleartext.mkv
        """
        let service = NTVIPTVCatalogService { _ in Data(text.utf8) }
        let config = try self.config(playlist: "https://provider.example/list.m3u")
        let page = try await service.catalog(config: config, type: "series", search: nil, skip: nil)
        XCTAssertEqual(page.count, 1)
        let meta = try await service.meta(config: config, type: "series", id: page[0].id)
        XCTAssertEqual(meta.videos?.map(\.episode), [1, 2])
        let streams = try await service.streams(config: config, type: "series", id: XCTUnwrap(meta.videos?.first?.id))
        XCTAssertEqual(streams.first?.behaviorHints?.proxyHeaders?.request?["User-Agent"], "nTV-test")
    }

    func testM3UMovieRoutingExcludesTVUnsafeURLsAndUnsupportedDRM() async throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 media-type="movie",Film
        https://provider.example/movie/1.mkv
        #EXTINF:-1 media-type="tv",Live
        https://provider.example/live/1.m3u8
        #EXTINF:-1 media-type="movie",Insecure
        http://provider.example/movie/2.mkv
        #EXTINF:-1 media-type="movie",DRM
        #KODIPROP:inputstream.adaptive.license_type=com.widevine.alpha
        https://provider.example/movie/3.mpd
        """
        let service = NTVIPTVCatalogService { _ in Data(text.utf8) }
        let page = try await service.catalog(config: config(playlist: "https://provider.example/list.m3u"), type: "movie", search: nil, skip: nil)
        XCTAssertEqual(page.map(\.name), ["Film"])
    }

    func testProviderFailuresAndHTMLAreErrorsRatherThanEmptyCatalogEvidence() async throws {
        for data in [Data("<html>Login</html>".utf8), Data(#"{"error":"denied"}"#.utf8)] {
            let service = NTVIPTVCatalogService { _ in data }
            do {
                _ = try await service.catalog(config: config(), type: "movie", search: nil, skip: nil)
                XCTFail("Malformed provider payload must fail.")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
    }

    func testProviderCatalogCountIsBounded() async throws {
        let data = try JSONSerialization.data(withJSONObject: Array(repeating: ["stream_id": 1, "name": "Film"], count: 10_001))
        let service = NTVIPTVCatalogService { _ in data }
        do {
            _ = try await service.catalog(config: config(), type: "movie", search: nil, skip: nil)
            XCTFail("Oversized catalogs must fail.")
        } catch StremioAPIError.responseTooLarge { } catch { XCTFail("Unexpected error type.") }
    }

    func testAccountValidationAcceptsVODOnlyAccountsAndRejectsExpiredOrDeniedAccounts() async throws {
        let config = try config()
        let active = NTVIPTVCatalogService { url in
            XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" })
            return Data(#"{"user_info":{"auth":1,"status":"Active"}}"#.utf8)
        }
        try await active.validateAccount(config: config)
        for info in [#"{"auth":0,"status":"Active"}"#, #"{"auth":1,"status":"Expired"}"#] {
            let rejected = NTVIPTVCatalogService { _ in Data(("{\"user_info\":" + info + "}").utf8) }
            do { try await rejected.validateAccount(config: config); XCTFail("Account must be refused.") }
            catch StremioAPIError.invalidResponse { } catch { XCTFail("Unexpected error type.") }
        }
    }

    func testInternalIPTVIDsCannotFallThroughToAnExternalAddon() async throws {
        let config = try config()
        let addon = InstalledAddon(manifestURL: "https://external.example/manifest.json",
            manifest: AddonManifest(id: "external", name: "External", version: nil, description: nil, logo: nil, types: ["movie"], idPrefixes: nil, catalogs: nil, resources: [.simple("stream")]))
        XCTAssertFalse(addon.handles(id: config.prefix + "movie.1"))
        do {
            _ = try await StremioAPI.streams(addon: addon, type: "movie", id: config.prefix + "movie.1")
            XCTFail("Internal IDs must be rejected before network access.")
        } catch StremioAPIError.invalidResponse { } catch { XCTFail("Unexpected error type.") }
        let service = NTVIPTVCatalogService { _ in XCTFail("Foreign IDs must not fetch."); return Data() }
        do {
            _ = try await service.streams(config: config, type: "movie", id: "ntv.iptv.foreign.movie.1")
            XCTFail("A different source must not resolve.")
        } catch StremioAPIError.invalidResponse { } catch { XCTFail("Unexpected error type.") }
    }

    @MainActor
    func testRoutingChangesInvalidateSearchResultsButAnUnchangedRoutingDoesNot() {
        let model = SearchViewModel()
        model.updateSourceConfiguration("source-A.tv")
        model.query = "Film"
        let item = MetaItem(id: "local", type: "movie", name: "Film")
        model.results = [item]; model.trending = [item]
        model.updateSourceConfiguration("source-A.tv")
        XCTAssertEqual(model.results.map(\.id), ["local"])
        model.updateSourceConfiguration("source-A.movie")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.trending.isEmpty)
        XCTAssertEqual(model.query, "Film")
    }

    func testAnOlderProviderResponseCannotReplaceTheNewSourcesCache() async throws {
        let started = expectation(description: "Old provider request is suspended")
        let probe = NTVIPTVDelayedReply(started: started)
        let service = NTVIPTVCatalogService { url in await probe.load(url) }
        let old = try config(playlist: "https://old.example/get.php?username=demo&password=demo")
        let new = try config(playlist: "https://new.example/get.php?username=demo&password=demo")
        let pending = Task { try await service.catalog(config: old, type: "movie", search: nil, skip: nil) }
        await fulfillment(of: [started], timeout: 2)
        let current = try await service.catalog(config: new, type: "movie", search: nil, skip: nil)
        await probe.finish()
        do { _ = try await pending.value; XCTFail("Stale source reply must be rejected.") }
        catch is CancellationError { } catch { XCTFail("Unexpected error type.") }
        XCTAssertTrue(current.first?.id.hasPrefix(new.prefix) == true)
        let repeated = try await service.catalog(config: new, type: "movie", search: nil, skip: nil)
        XCTAssertEqual(repeated.map(\.id), current.map(\.id))
    }
}

private actor NTVIPTVDelayedReply {
    private var pending: CheckedContinuation<Data, Never>?
    private let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    private let data = Data(#"[{"stream_id":1,"name":"Film"}]"#.utf8)
    func load(_ url: URL) async -> Data {
        if url.host == "old.example" { return await withCheckedContinuation { pending = $0; started.fulfill() } }
        return data
    }
    func finish() { pending?.resume(returning: data); pending = nil }
}

final class NTVCoreTests: XCTestCase {
    func testSeanimeNavigationStartsOnTheLeftWithoutReplacingReferencePreferences() throws {
        let suite = "ntv.seanime.navigation.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = Data("reference-layout-with-top-menu".utf8)
        defaults.set(reference, forKey: "orivio.homecatalog.v1")
        XCTAssertEqual(NTVInterfaceVariant.navigation(profileID: 1, defaults: defaults), .left)
        NTVInterfaceVariant.saveNavigation(.top, profileID: 1, defaults: defaults)
        XCTAssertEqual(NTVInterfaceVariant.navigation(profileID: 1, defaults: defaults), .top)
        XCTAssertEqual(defaults.data(forKey: "orivio.homecatalog.v1"), reference,
                       "Trying the new interface must preserve the old layout for rollback.")
    }

    func testSeanimeNavigationChoiceDoesNotLeakAcrossProfiles() throws {
        let suite = "ntv.seanime.profiles.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        NTVInterfaceVariant.saveNavigation(.top, profileID: 1, defaults: defaults)
        XCTAssertEqual(NTVInterfaceVariant.navigation(profileID: 2, defaults: defaults), .left)
        NTVInterfaceVariant.saveNavigation(.left, profileID: 2, defaults: defaults)
        XCTAssertEqual(NTVInterfaceVariant.navigation(profileID: 1, defaults: defaults), .top)
        defaults.set("unknown-future-value", forKey: NTVInterfaceVariant.navigationKey(profileID: 2))
        XCTAssertEqual(NTVInterfaceVariant.navigation(profileID: 2, defaults: defaults), .left)
    }

    func testSourceStatusDoesNotConfuseHealthyEmptyPartialAndTotalOutages() {
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 2, failures: 0), .empty)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 2, failures: 1), .incomplete)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 2, failures: 2), .unavailable)
        // Two configurations with the same display name are still two requests.
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 3, failures: 2), .incomplete)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 0, failures: 0), .noCompatibleAddon)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 0, failures: 0, unavailableManifests: 1), .unavailable)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: true, requests: 1, failures: 0), .unreleased)
        XCTAssertEqual(NTVSourceStatus.resolve(unreleased: false, requests: 1, failures: 0, filtered: true), .filtered)
    }

    func testSourceErrorReasonsNeverEchoURLsOrErrorUserInfo() {
        let privateURL = "https://example.invalid/config/test-credential/stream.json"
        let error = URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLStringErrorKey: privateURL,
            NSLocalizedDescriptionKey: "failed " + privateURL])
        XCTAssertEqual(StreamsViewModel.shortReason(for: error), "connexion à l’addon impossible")
        XCTAssertEqual(StreamsViewModel.shortReason(for: StremioAPIError.badURL(privateURL)), "adresse de l’addon invalide")
        XCTAssertEqual(StreamsViewModel.shortReason(for: URLError(.timedOut)), "délai de réponse dépassé")
        XCTAssertEqual(StreamsViewModel.shortReason(for: StremioAPIError.badResponse(403)), "accès refusé (HTTP 403)")
    }

    @MainActor
    func testUnreleasedSourceMessageUsesTheEpisodeDateBeforeTheSeriesPremiere() {
        let show = MetaItem(id: "show", type: "series", name: "Série", released: "2020-01-01T00:00:00Z")
        let episode = MetaVideo(id: "show:1:2", title: "Épisode", season: 1, episode: 2, released: "2999-01-01T00:00:00Z")
        XCTAssertEqual(StreamsViewModel(meta: show, video: episode).emptyStatus, .unreleased)
        let unknown = MetaItem(id: "unknown", type: "movie", name: "Date inconnue")
        XCTAssertNotEqual(StreamsViewModel(meta: unknown, video: nil).emptyStatus, .unreleased)
        let future = MetaItem(id: "future", type: "movie", name: "Film", released: "2999-01-01T00:00:00Z")
        XCTAssertEqual(StreamsViewModel(meta: future, video: nil).emptyStatus, .unreleased)
    }

    @MainActor
    func testRecentSearchesPersistPerProfileAndCanBeRemovedWithoutAffectingOthers() throws {
        let suite = "ntv.recent.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = NTVRecentSearches(defaults: defaults)
        history.record("  Silo  ", profile: 1)
        history.record("Le   voyage de Chihiro", profile: 1)
        history.record("silo", profile: 1)
        history.record("Frieren", profile: 2)
        XCTAssertEqual(NTVRecentSearches(defaults: defaults).queries(profile: 1), ["silo", "Le voyage de Chihiro"])
        XCTAssertEqual(history.queries(profile: 2), ["Frieren"])
        history.remove("SILO", profile: 1)
        XCTAssertEqual(history.queries(profile: 1), ["Le voyage de Chihiro"])
        history.clear(profile: 1)
        XCTAssertTrue(history.queries(profile: 1).isEmpty)
        XCTAssertEqual(history.queries(profile: 2), ["Frieren"])
        XCTAssertNil(defaults.object(forKey: "ntv.search.recent.v1"), "There must be no shared fallback across profiles.")
    }

    @MainActor
    func testRecentSearchesRejectSensitivePastesAndBoundStorage() throws {
        let suite = "ntv.recent.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = NTVRecentSearches(defaults: defaults)
        for input in ["https://example.invalid/private/config", "Bearer test-value", "api_key=test-value",
                      "person@example.invalid", String(repeating: "a", count: 40), "a", "ab\u{0000}cd"] {
            history.record(input, profile: 1)
        }
        XCTAssertTrue(history.queries(profile: 1).isEmpty)
        for number in 0..<20 { history.record("Film \(number)", profile: 1) }
        XCTAssertEqual(history.queries(profile: 1).count, NTVRecentSearches.limit)
        XCTAssertEqual(history.queries(profile: 1).first, "Film 19")
        XCTAssertEqual(NTVRecentSearches.title("Mr. Robot"), "Mr. Robot")
        defaults.set(Data(repeating: 0, count: 8193), forKey: ProfileScopedDefaults.key("ntv.search.recent.v1", 2))
        XCTAssertTrue(history.queries(profile: 2).isEmpty)
    }

    @MainActor
    func testResumeSuggestionIsOncePerProfileAndAnEmptyLoadDoesNotConsumeIt() throws {
        let suite = "ntv.resume.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = NTVResumeSuggestion(defaults: defaults)
        session.setMode(.latest, profile: 1)
        session.setMode(.latest, profile: 2)
        let now = Date(timeIntervalSince1970: 1_000_000)
        func row(_ id: String, position: Double = 180, duration: Double = 3600, date: Date? = nil) -> WatchProgress {
            WatchProgress(id: id, metaID: id, type: "movie", name: "Film", poster: nil,
                background: nil, logo: nil, season: nil, episode: nil, episodeTitle: nil,
                positionSeconds: position, durationSeconds: duration, updatedAt: date ?? now)
        }
        XCTAssertNil(session.claim(profile: 1, items: [], now: now))
        let rows = [row("older", date: now.addingTimeInterval(-100)), row("latest")]
        XCTAssertEqual(session.claim(profile: 1, items: rows, now: now)?.id, "latest")
        XCTAssertNil(session.claim(profile: 1, items: rows, now: now))
        XCTAssertEqual(session.claim(profile: 2, items: [row("other-profile")], now: now)?.id, "other-profile")
        XCTAssertNil(NTVResumeSuggestion.latest(in: [row("finished", position: 3500),
            row("next-up", position: 0), row("invalid", position: .nan),
            row("unknown", duration: .infinity), row("future", date: now.addingTimeInterval(120)),
            row("stale", date: now.addingTimeInterval(-31 * 86400))], now: now))
        XCTAssertEqual(NTVResumeSuggestion.latest(in: [row("a"), row("b")], now: now)?.id, "b")
    }

    @MainActor
    func testADeferredCatalogEntryCanBeClaimedOnlyOnceAcrossRemounts() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        XCTAssertTrue(router.isPendingEntry(request))
        XCTAssertTrue(router.consumeEntry(request))
        XCTAssertFalse(router.isPendingEntry(request))
        XCTAssertFalse(router.consumeEntry(request), "Remounting with the same task ID must not replay an old category selection.")
    }

    @MainActor
    func testANewerCategoryRequestSurvivesAnOlderViewsCleanupAndClaim() {
        let router = ContentFocusRouter()
        let old = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        let current = router.makeEntryRequest(in: "ntv.catalog.shelf.b")
        router.cancelEntry(old)
        XCTAssertFalse(router.consumeEntry(old))
        XCTAssertTrue(router.isPendingEntry(current))
        XCTAssertTrue(router.consumeEntry(current))
    }

    @MainActor
    func testMovingWithinTheDestinationCancelsItsUnclaimedRestoration() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        router.noteUserMovement(in: "ntv.catalog.shelf.a")
        XCTAssertFalse(router.consumeEntry(request), "A delayed detail return must yield to the viewer's next movement.")
    }

    @MainActor
    func testTheDepartingRowsLateCommandDoesNotInvalidateTheNewEntry() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.b")
        router.noteUserMovement(in: "ntv.catalog.shelf.a")
        XCTAssertTrue(router.consumeEntry(request), "The command that caused a transfer may arrive after its failed-move notification.")
    }

    @MainActor
    func testEnteringAnotherRowInvalidatesAnUnclaimedCatalogRequest() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        router.noteFocused(row: "ntv.catalog.shelf.b")
        XCTAssertFalse(router.consumeEntry(request), "A lazy row must not reclaim focus after native navigation has already moved elsewhere.")
    }

    @MainActor
    func testDetailRestorationSurvivesNativeFallbackButYieldsToMovementInAnyRow() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.remembered", kind: .restoration)
        router.noteFocused(row: "ntv.catalog.shelf.nearby")
        XCTAssertTrue(router.hasPendingRestoration)
        XCTAssertTrue(router.isPendingEntry(request), "An automatic pop-transition fallback must not lose the remembered poster.")
        router.noteUserMovement(in: "ntv.catalog.shelf.nearby")
        XCTAssertFalse(router.hasPendingRestoration)
        XCTAssertFalse(router.consumeEntry(request), "A real command in the fallback row must prevent a later pull back.")
    }

    @MainActor
    func testNativeEntryIntoTheRequestedRowKeepsItsPendingRestoration() {
        let router = ContentFocusRouter()
        let request = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        router.noteFocused(row: "ntv.catalog.shelf.a")
        XCTAssertTrue(router.isPendingEntry(request))
        XCTAssertTrue(router.consumeEntry(request))
        router.land(in: "ntv.catalog.shelf.a", assign: {}, landed: { false })
        XCTAssertTrue(router.isLanding(in: "ntv.catalog.shelf.a"), "An explicit restoration owns the destination while the lazy poster mounts.")
        XCTAssertFalse(router.isLanding(in: "ntv.catalog.shelf.b"))
        router.cancelLanding()
        XCTAssertFalse(router.isLanding(in: "ntv.catalog.shelf.a"))
    }

    @MainActor
    func testUnmountingOrLeavingThePageInvalidatesAnUnclaimedEntry() {
        let router = ContentFocusRouter()
        let first = router.makeEntryRequest(in: "ntv.catalog.shelf.a")
        router.unregister("ntv.catalog.shelf.a")
        XCTAssertFalse(router.consumeEntry(first))
        let second = router.makeEntryRequest(in: "ntv.catalog.shelf.b")
        router.noteUserMovement()
        XCTAssertFalse(router.consumeEntry(second), "Opening a menu or changing page supersedes all pending catalog entry work.")
    }

    @MainActor
    func testCategoryHeaderHasDistinctFailedMoveOwnershipFromPosterShelves() {
        let router = ContentFocusRouter()
        router.noteFocused(row: "ntv.catalog.shelf.a")
        XCTAssertTrue(router.hasCatalogRowFocus)
        let pending = router.makeEntryRequest(in: "ntv.catalog.shelf.a", kind: .restoration)
        router.noteFocused(row: "ntv.catalog.movie.entry")
        XCTAssertFalse(router.hasCatalogRowFocus, "The Categories trigger must allow Up to reach the top navigation.")
        XCTAssertFalse(router.consumeEntry(pending), "Focusing Categories must invalidate a pending poster landing.")
        router.noteFocused(row: "fixture.row.0")
        XCTAssertFalse(router.hasCatalogRowFocus, "Home retains its existing native boundary routing.")
    }

    @MainActor
    func testANewRemoteMovementCancelsSameRowRetriesAndInvalidatesPendingRestoration() async throws {
        let router = ContentFocusRouter()
        var assignments = 0
        let restoreGeneration = router.interactionGeneration
        router.land(in: "row-a", assign: { assignments += 1 }, landed: { false })
        router.noteUserMovement()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(assignments, 1, "Right after arriving in a row must not be followed by a pull back to its start.")
        XCTAssertNotEqual(router.interactionGeneration, restoreGeneration)
    }
    @MainActor
    func testTheDepartingRowsMoveNotificationCannotCancelTheNewRowsLanding() async throws {
        let router = ContentFocusRouter()
        var assignments = 0
        let retried = expectation(description: "The destination keeps its deferred landing")
        router.land(in: "row-b", assign: {
            assignments += 1
            if assignments == 2 { retried.fulfill() }
        }, landed: { false })
        router.noteUserMovement(in: "row-a")
        await fulfillment(of: [retried], timeout: 2)
        XCTAssertGreaterThan(assignments, 1)
        router.noteUserMovement(in: "row-b")
        let stoppedAt = assignments
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(assignments, stoppedAt)
    }

    @MainActor
    func testADeferredFocusLandingCannotPullTheUserBackFromAnotherRow() async throws {
        let router = ContentFocusRouter()
        var oldAssignments = 0
        router.land(in: "row-a", assign: { oldAssignments += 1 }, landed: { false })
        XCTAssertEqual(oldAssignments, 1)
        router.noteFocused(row: "row-b")
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(oldAssignments, 1, "An old landing must never reassign focus after another row takes it.")
    }

    @MainActor
    func testANewerLandingCancelsThePreviousRowsRetries() async throws {
        let router = ContentFocusRouter()
        var first = 0
        var second = 0
        router.land(in: "row-a", assign: { first += 1 }, landed: { false })
        router.land(in: "row-b", assign: { second += 1 }, landed: { true })
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    @MainActor
    func testUnmountingARowCancelsItsDeferredScrollAndFocusWork() async throws {
        let router = ContentFocusRouter()
        var assignments = 0
        router.register("row-a") { true }
        router.land(in: "row-a", assign: { assignments += 1 }, landed: { false })
        router.unregister("row-a")
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(assignments, 1)
    }

    func testNuvioRuntimePortFloorsTimeAndTogglesRemainingWithoutNegativeDurations() {
        XCTAssertEqual(NTVNuvioRuntime.time(0), "00:00")
        XCTAssertEqual(NTVNuvioRuntime.time(59.99), "00:59")
        XCTAssertEqual(NTVNuvioRuntime.time(3601.8), "1:00:01")
        XCTAssertEqual(NTVNuvioRuntime.text(position: 373, duration: 5842, remaining: false), "06:13 / 1:37:22")
        XCTAssertEqual(NTVNuvioRuntime.text(position: 373, duration: 5842, remaining: true), "−1:31:09")
        XCTAssertEqual(NTVNuvioRuntime.text(position: 120, duration: 90, remaining: true), "−00:00")
        XCTAssertEqual(NTVNuvioRuntime.text(position: -20, duration: -30, remaining: true), "−00:00")
        XCTAssertEqual(NTVNuvioRuntime.time(.infinity), "00:00")
        XCTAssertEqual(NTVNuvioRuntime.time(.nan), "00:00")
    }

    func testPrimaryIconNameUsesTheCompiledReference() {
        XCTAssertEqual(NTVSystemIconManifest.primaryName(in: ["CFBundleIcons": ["CFBundlePrimaryIcon": "NTVPrimaryIconV2"]]), "NTVPrimaryIconV2")
        XCTAssertEqual(NTVSystemIconManifest.primaryName(in: ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "NTVPrimaryIconV2"]]]), "NTVPrimaryIconV2")
        XCTAssertNil(NTVSystemIconManifest.primaryName(in: ["CFBundleIcons": ["CFBundlePrimaryIcon": 39]]))
        XCTAssertNil(NTVSystemIconManifest.primaryName(in: [:]))
    }

    func testFrameCadenceSeparatesARegularRateFromLongMainLoopGaps() {
        var regular = FrameCadenceWindow()
        XCTAssertNil(regular.record(timestamp: 0, expectedInterval: 1.0 / 60))
        var result: FrameCadenceSnapshot?
        for tick in 1...60 { result = regular.record(timestamp: Double(tick) / 60, expectedInterval: 1.0 / 60) ?? result }
        XCTAssertEqual(result?.callbacksPerSecond, 60)
        XCTAssertEqual(result?.lateCallbacks, 0)
        XCTAssertEqual(result?.worstGapMilliseconds ?? 0, 1000.0 / 60, accuracy: 0.001)
        var delayed = FrameCadenceWindow()
        _ = delayed.record(timestamp: 0, expectedInterval: 1.0 / 60)
        _ = delayed.record(timestamp: 0.2, expectedInterval: 1.0 / 60)
        let late = delayed.record(timestamp: 1, expectedInterval: 1.0 / 60)
        XCTAssertEqual(late?.lateCallbacks, 2)
        XCTAssertEqual(late?.worstGapMilliseconds ?? 0, 800, accuracy: 0.001)
        XCTAssertEqual(late?.callbacksPerSecond, 2)
    }

    func testFrameCadenceRejectsInvalidInputsAndResetsABackwardsClock() {
        var window = FrameCadenceWindow()
        XCTAssertNil(window.record(timestamp: .nan, expectedInterval: 1.0 / 60))
        XCTAssertNil(window.record(timestamp: 1, expectedInterval: 0))
        XCTAssertNil(window.record(timestamp: 1, expectedInterval: 1.0 / 60))
        XCTAssertNil(window.record(timestamp: 0, expectedInterval: 1.0 / 60))
        XCTAssertNil(window.record(timestamp: 0, expectedInterval: 1.0 / 60))
        XCTAssertEqual(window.record(timestamp: 1, expectedInterval: 1.0 / 60)?.callbacksPerSecond, 1)
    }

    func testSystemIconAcceptsTheActualMergedDictionaryAndTVArray() {
        let name = "NTVSystemIcon"
        XCTAssertTrue(NTVSystemIconManifest.declares(name, in: ["CFBundleIcons": [
            "CFBundlePrimaryIcon": "NTVPrimaryIcon",
            "CFBundleAlternateIcons": [name: ["CFBundleIconName": name]]]]))
        XCTAssertTrue(NTVSystemIconManifest.declares(name, in: ["CFBundleIcons": [
            "CFBundleAlternateIcons": [name]]]))
        XCTAssertFalse(NTVSystemIconManifest.declares(name, in: ["CFBundleIcons": [
            "CFBundleAlternateIcons": [name: ["CFBundleIconName": "OtherIcon"]]]]))
        XCTAssertFalse(NTVSystemIconManifest.declares(name, in: [:]))
    }

    func testSystemIconRecognizerAcceptsTheRealHostBundleDeclaration() {
        XCTAssertTrue(NTVSystemIconManifest.declares("NTVSystemIcon", in: Bundle.main.infoDictionary ?? [:]),
                      "The runtime recognizer must accept the actual Xcode-merged app plist, not just actool's intermediate plist.")
    }

    @MainActor
    func testCompiledAppSupportsTheSystemIconAPI() {
        XCTAssertTrue(UIApplication.shared.supportsAlternateIcons,
                      "Recognizing plist entries alone must not mask a declaration UIKit cannot use.")
    }

    func testFutureAddonDateDoesNotOverwriteTheDisplayYearAndSurvivesIdentityRepair() throws {
        let future = try JSONDecoder().decode(MetaItem.self, from: Data(#"{"id":"future","type":"movie","name":"Future","releaseInfo":"2026","released":"2999-01-01T00:00:00Z"}"#.utf8))
        XCTAssertEqual(future.releaseInfo, "2026")
        XCTAssertTrue(future.isUnreleased)
        XCTAssertTrue(future.withID("canonical").isUnreleased)
        let restored = try JSONDecoder().decode(MetaItem.self, from: JSONEncoder().encode(future))
        XCTAssertEqual(restored.released, future.released)
        XCTAssertFalse(MetaItem(id: "unknown", type: "movie", name: "Unknown").isUnreleased)
    }

    func testAvailabilityUsesAllSourcesAndNeverTreatsFailureAsAbsence() async throws {
        func addon(_ id: String) throws -> InstalledAddon {
            let manifest = try JSONDecoder().decode(AddonManifest.self, from: JSONSerialization.data(withJSONObject:
                ["id": id, "name": "Fixture", "version": "1", "types": ["movie", "series"], "resources": ["stream"]]))
            return InstalledAddon(manifestURL: "https://example.invalid/\(id)/manifest.json", manifest: manifest)
        }
        let sources = try [addon("empty"), addon("available")]
        let item = MetaItem(id: "title", type: "movie", name: "Fixture")
        let stream = try JSONDecoder().decode(Stream.self, from: Data(#"{"url":"https://example.invalid/video.mp4"}"#.utf8))
        let store = NTVSourceAvailabilityStore()
        let positive = try await store.check(item: item, sources: sources, scope: "positive") { addon, _, _ in
            addon.manifest.id == "available" ? [stream] : []
        }
        XCTAssertEqual(positive, .available, "One source must preserve the title even when another returns empty.")
        let absent = try await store.check(item: item, sources: sources, scope: "empty") { _, _, _ in [] }
        XCTAssertEqual(absent, .absent)
        let uncertain = try await store.check(item: item, sources: sources, scope: "failed") { addon, _, _ in
            if addon.manifest.id == "available" { throw URLError(.timedOut) }
            return []
        }
        XCTAssertEqual(uncertain, .unknown)
        let unconfigured = try await store.check(item: item, sources: [], scope: "none") { _, _, _ in XCTFail("No unconfigured request"); return [] }
        XCTAssertEqual(unconfigured, .unknown)
        let unresolved = try await store.check(item: MetaItem(id: "tmdb:123", type: "movie", name: "Fixture"),
            sources: sources, scope: "unresolved") { _, _, _ in
            XCTFail("An unresolved TMDB ID must not be queried or treated as proof of absence.")
            return []
        }
        XCTAssertEqual(unresolved, .unknown)
        XCTAssertNotEqual(NTVSourceAvailabilityStore.scope(profile: 1, addons: sources),
                          NTVSourceAvailabilityStore.scope(profile: 2, addons: sources))
    }

    func testAvailabilityCannotHideAWholeSeriesAfterOnlyCheckingItsFirstEpisodes() async throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["series"],"resources":["stream"]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        let item = try JSONDecoder().decode(MetaItem.self, from: Data(#"{"id":"series","type":"series","name":"Fixture","videos":[{"id":"series:1:1","season":1,"episode":1,"released":"2000-01-01"},{"id":"series:1:2","season":1,"episode":2,"released":"2000-01-01"},{"id":"series:1:3","season":1,"episode":3,"released":"2000-01-01"},{"id":"series:1:4","season":1,"episode":4,"released":"2000-01-01"}]}"#.utf8))
        let store = NTVSourceAvailabilityStore()
        let result = try await store.check(item: item, sources: [addon], scope: "series") { _, _, _ in [] }
        XCTAssertEqual(result, .unknown, "A later season or episode may still be playable.")
        let resumed = try JSONDecoder().decode(MetaItem.self, from: Data(#"{"id":"tt1234567","type":"series","name":"Fixture","videos":[{"id":"tt1234567","season":1,"episode":2,"released":"2000-01-01"}]}"#.utf8))
        let playable = try JSONDecoder().decode(Stream.self, from: Data(#"{"url":"https://example.invalid/video.mp4"}"#.utf8))
        let canonical = try await store.check(item: resumed, sources: [addon], scope: "resumed") { _, _, id in
            XCTAssertEqual(id, "tt1234567:1:2", "Availability must use the same episode identity as playback.")
            return id == "tt1234567:1:2" ? [playable] : []
        }
        XCTAssertEqual(canonical, .available)
    }

    func testHomeRecommendationsUseXperienceIdentityAndEnabledCatalogs() throws {
        func addon(_ id: String, name: String = "Fixture", enabled: Bool = true) throws -> InstalledAddon {
            let manifest = try JSONDecoder().decode(AddonManifest.self, from: JSONSerialization.data(withJSONObject: [
                "id": id, "name": name, "version": "1", "types": ["movie"],
                "resources": ["catalog"], "catalogs": [["type": "movie", "id": "latest"]]
            ]))
            return InstalledAddon(manifestURL: "https://example.invalid/\(id)/manifest.json", manifest: manifest, enabled: enabled)
        }
        let configured = try addon("app.xperience.configured-fixture")
        let another = try addon("APP.XPERIENCE.second-fixture")
        let cinemeta = try addon("com.linvo.cinemeta")
        let sameName = try addon("unrelated.provider", name: "XPERIENCE")
        let similarPrefix = try addon("app.xperience-other")
        let disabled = try addon("app.xperience.disabled", enabled: false)
        let available = [cinemeta, configured, sameName, another, disabled, similarPrefix]
        XCTAssertEqual(NTVHomeSources.recommendations(from: available), [configured, another])
        XCTAssertEqual(available.count, 6, "Home selection must not remove providers used by other sections.")
        XCTAssertTrue(NTVHomeSources.recommendations(from: [cinemeta, sameName]).isEmpty,
                      "A missing XPERIENCE must not silently fall back to another provider.")
    }

    @MainActor
    func testCatalogShelvesReuseTheirStateAcrossVisitsAndSeparateProfiles() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["movie","series"],"resources":["catalog"],"catalogs":[{"type":"movie","id":"new","name":"Latest"},{"type":"series","id":"new"},{"type":"movie","id":"search","extraRequired":["search"]}]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        let model = NTVCatalogBrowserModel()
        model.configure(addons: [addon], type: "movie", scope: "1")
        XCTAssertEqual(model.sources.count, 1, "Search-only catalogs and other media types must not create shelves.")
        let source = try XCTUnwrap(model.sources.first), shelf = model.shelf(source)
        model.rememberSelection(sourceID: source.id, itemID: "selected-fixture")
        model.configure(addons: [addon], type: "movie", scope: "1")
        XCTAssertTrue(shelf === model.shelf(source), "Returning from a detail must retain loaded catalog state.")
        XCTAssertEqual(model.lastSelection?.itemID, "selected-fixture", "A tab round-trip must retain the selected poster without a new catalog request.")
        model.configure(addons: [addon], type: "movie", scope: "2")
        XCTAssertFalse(shelf === model.shelf(source), "A different profile must not inherit the former profile's cache.")
        XCTAssertNil(model.lastSelection, "Focus must not cross profile boundaries.")
    }

    @MainActor
    func testCatalogEntrySkipsAFilteredEmptyRowAndForgetsItForAnotherProfile() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["movie"],"resources":["catalog"],"catalogs":[{"type":"movie","id":"first"},{"type":"movie","id":"second"},{"type":"movie","id":"third"}]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        let model = NTVCatalogBrowserModel()
        model.configure(addons: [addon], type: "movie", scope: "profile-one")
        let first = try XCTUnwrap(model.sources.first?.id)
        let second = model.sources[1].id
        let third = model.sources[2].id
        model.noteVisibleStart(sourceID: first, itemID: nil)
        XCTAssertEqual(model.firstNavigableSourceID, second)
        model.noteVisibleStart(sourceID: first, itemID: "visible")
        XCTAssertEqual(model.firstNavigableSourceID, first)
        model.noteVisibleStart(sourceID: second, itemID: nil)
        XCTAssertEqual(model.adjacentNavigableSourceID(to: first, forward: true), third)
        XCTAssertEqual(model.adjacentNavigableSourceID(to: third, forward: false), first)
        XCTAssertNil(model.adjacentNavigableSourceID(to: third, forward: true))
        model.noteVisibleStart(sourceID: first, itemID: nil)
        model.noteVisibleStart(sourceID: third, itemID: nil)
        XCTAssertEqual(model.firstNavigableSourceID, first, "An entirely filtered gallery must keep its Categories recovery action reachable.")
        model.configure(addons: [addon], type: "movie", scope: "profile-two")
        XCTAssertEqual(model.firstNavigableSourceID, first)
    }

    @MainActor
    func testCatalogEntryUsesThePreviousRowEvenWhenLocalFocusWasRetained() {
        let first = "ntv.catalog.shelf.first", second = "ntv.catalog.shelf.second"
        XCTAssertTrue(ContentFocusRouter.startsCatalogRow(previousItem: "remembered-tenth-poster", previousRow: first,
            currentRow: second, restorationItem: nil), "A retained local focus value must not bypass first-poster entry from another row.")
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: "remembered-tenth-poster", previousRow: second,
            currentRow: second, restorationItem: nil), "An ordinary step inside the row must stay native.")
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: "remembered-tenth-poster", previousRow: first,
            currentRow: second, restorationItem: "remembered-tenth-poster"), "An explicit detail restoration must still retain its chosen poster.")
    }

    @MainActor
    func testCatalogTouchEntryDoesNotResetHorizontalFocusOrDetailRestoration() {
        let first = "ntv.catalog.shelf.first", second = "ntv.catalog.shelf.second"
        XCTAssertTrue(ContentFocusRouter.startsCatalogRow(previousItem: nil, previousRow: first,
            currentRow: second, restorationItem: nil))
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: "second-poster", previousRow: second,
            currentRow: second, restorationItem: nil), "A horizontal or diagonal move inside a row stays where the viewer chose.")
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: nil, previousRow: first,
            currentRow: second, restorationItem: "remembered"), "Returning from a detail preserves its poster.")
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: nil, previousRow: second,
            currentRow: second, restorationItem: nil))
        XCTAssertFalse(ContentFocusRouter.startsCatalogRow(previousItem: nil, previousRow: "home",
            currentRow: second, restorationItem: nil), "The root router owns entry from other pages.")
    }

    func testAvailabilityRequiresAnExplicitValidEmptyList() throws {
        let decoder = JSONDecoder()
        let source = try XCTUnwrap(URL(string: "https://example.invalid/stream/movie/fixture.json"))
        func probeResponse(_ payload: String) throws -> StremioAPI.AvailabilityStreamsResponse {
            let checked = try NTVAddonPayloadPolicy.checkedData(Data(payload.utf8), resource: .availabilityStreams, source: source)
            return try decoder.decode(StremioAPI.AvailabilityStreamsResponse.self, from: checked)
        }
        let empty = try probeResponse(#"{"streams":[]}"#)
        XCTAssertTrue(empty.streams.isEmpty)
        for payload in [#"{}"#, #"{"streams":null}"#, #"{"streams":[null]}"#, #"{"streams":[42]}"#,
                        #"{"streams":[{"url":"javascript:alert(1)"}]}"#,
                        #"{"streams":[{"title":"Provider error"}]}"#] {
            XCTAssertThrowsError(try probeResponse(payload))
        }
        let playable = try probeResponse(#"{"streams":[{"url":"https://example.invalid/video.mp4"}]}"#)
        XCTAssertEqual(playable.streams.count, 1)
        let tolerantPayload = try NTVAddonPayloadPolicy.checkedData(
            Data(#"{"streams":[null,{"url":"https://example.invalid/video.mp4"}]}"#.utf8), resource: .streams, source: source)
        let tolerant = try decoder.decode(StreamsResponse.self, from: tolerantPayload)
        XCTAssertEqual(tolerant.streams?.count, 1, "Normal Sources keeps its existing tolerant behavior.")
    }

    @MainActor
    func testCatalogPreviewIsBoundedDeduplicatedAndDoesNotReloadOnReturn() async throws {
        let addon = try fixtureAddon(), source = NTVCatalogSource(addon: addon, catalog: try catalog(type: "movie"))
        let fixture = CatalogPreviewFixture()
        let shelf = NTVCatalogShelfModel(source: source, scope: UUID().uuidString) { _ in
            await fixture.page()
        }
        XCTAssertTrue(shelf.items.isEmpty, "Constructing an offscreen row must not request its catalog.")
        await shelf.load(); await shelf.load()
        let calls = await fixture.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(shelf.items.count, 24)
        XCTAssertEqual(Set(shelf.items.map(\.id)).count, 24)
        XCTAssertFalse(shelf.failed)
    }
    @MainActor
    func testDetailOpeningArtworkSurvivesLateProviderMetadata() {
        let model = DetailViewModel(item: MetaItem(id: "fixture", type: "movie", name: "Opening", poster: "https://example.invalid/poster.jpg", background: "https://example.invalid/catalog.jpg", logo: "https://example.invalid/first-logo.png"))
        model.meta = MetaItem(id: "fixture", type: "movie", name: "Enriched", poster: "https://example.invalid/new-poster.jpg", background: "https://example.invalid/alternate-crop.jpg", logo: "https://example.invalid/second-logo.png")
        XCTAssertEqual(model.openingBackground, "https://example.invalid/catalog.jpg")
        XCTAssertEqual(model.openingLogo, "https://example.invalid/first-logo.png")
        XCTAssertEqual(model.openingPoster, "https://example.invalid/poster.jpg",
                       "The Seanime detail cover must not swap crop after enrichment.")
        XCTAssertEqual(model.meta.name, "Enriched", "Metadata enrichment remains available.")
    }

    @MainActor
    func testDetailFallbackArtworkDoesNotSwitchFromPosterToBackdrop() {
        let model = DetailViewModel(item: MetaItem(id: "fixture", type: "movie", name: "Opening", poster: "https://example.invalid/poster.jpg"))
        model.meta = MetaItem(id: "fixture", type: "movie", name: "Enriched", background: "https://example.invalid/late.jpg", logo: "https://example.invalid/late-logo.png")
        XCTAssertEqual(model.openingBackground, "https://example.invalid/poster.jpg")
        XCTAssertNil(model.openingLogo)
        XCTAssertEqual(model.openingPoster, "https://example.invalid/poster.jpg")
    }
    @MainActor
    func testBlockedTouchCannotBeAdoptedWhenAnOverlayCloses() {
        let input = TouchHostView()
        var active = false
        var begins = 0, moves = 0, ends = 0
        input.configure(isActive: { active }, onBegan: { begins += 1 },
                        onMoved: { _, _ in moves += 1 }, onEnded: { _, _ in ends += 1 })
        input.receivePan(state: .began, translation: .zero)
        active = true
        input.receivePan(state: .changed, translation: .init(x: 500, y: 0))
        input.receivePan(state: .ended, translation: .init(x: 500, y: 0))
        XCTAssertEqual(begins, 0)
        XCTAssertEqual(moves, 0, "A gesture rejected at touch-down cannot move the playhead later")
        XCTAssertEqual(ends, 1, "The existing unconditional end still clears transport state")
        input.receivePan(state: .began, translation: .zero)
        input.receivePan(state: .changed, translation: .init(x: 20, y: 0))
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(moves, 1, "The next accepted contact remains usable")
    }

    @MainActor
    func testOverlayOpeningDuringTouchStillDeliversCancellationCleanup() {
        let input = TouchHostView()
        var active = true
        var moves = 0, ends = 0
        input.configure(isActive: { active }, onBegan: {},
                        onMoved: { _, _ in moves += 1 }, onEnded: { _, _ in ends += 1 })
        input.receivePan(state: .began, translation: .zero)
        input.receivePan(state: .changed, translation: .init(x: 20, y: 0))
        active = false
        input.receivePan(state: .changed, translation: .init(x: 80, y: 0))
        input.receivePan(state: .cancelled, translation: .init(x: 80, y: 0))
        XCTAssertEqual(moves, 1)
        XCTAssertEqual(ends, 1, "An interrupted contact must clear pan-in-flight flags even while input is blocked")
        active = true
        input.receivePan(state: .changed, translation: .init(x: 150, y: 0))
        XCTAssertEqual(moves, 1, "A late sample after cancellation is not a new contact")
    }

    @MainActor
    func testLaunchPresentationIsClaimedOnlyOncePerProcessSession() {
        let process = NTVLaunchSession()
        XCTAssertTrue(process.claim())
        XCTAssertFalse(process.claim(), "Returning from the background cannot replay the introduction.")
        XCTAssertFalse(process.claim(), "Rebuilding a scene cannot replay it either.")
        XCTAssertTrue(NTVLaunchSession().claim(), "A fresh app process can present its own introduction.")
    }

    func testPosterColumnsUseAvailableWidthAtDifferentTVSizes() {
        for width in [CGFloat(1280), 1920, 2560] {
            for preferred in [CGFloat(180), 210, 260] {
                let available = width - 2 * NTVViewport.horizontalInset
                let count = Int((available + NTVViewport.posterGap) / (preferred + NTVViewport.posterGap))
                let fitted = NTVViewport.posterWidth(available: available, preferred: preferred)
                XCTAssertEqual(CGFloat(count) * fitted + CGFloat(count - 1) * NTVViewport.posterGap,
                               available, accuracy: 0.01, "The last column cannot leave unused width.")
                XCTAssertGreaterThanOrEqual(fitted, preferred)
            }
        }
    }

    func testTouchScrubSlowDragKeepsScenePrecision() {
        let delta = NTVScrubMotion.delta(points: 2, elapsed: 0.1, duration: 7200)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertLessThanOrEqual(delta, 10, "A small slow drag must remain within a few seconds of the scene.")
    }

    func testTouchScrubFastSwipeRemainsBounded() {
        let slow = NTVScrubMotion.delta(points: 100, elapsed: 1, duration: 7200)
        let fast = NTVScrubMotion.delta(points: 100, elapsed: 0.1, duration: 7200)
        XCTAssertGreaterThan(fast, slow, "A faster swipe can move farther while remaining controllable.")
        XCTAssertLessThanOrEqual(fast, 5, "One projected remote sample cannot jump across the film.")
        XCTAssertEqual(NTVScrubMotion.delta(points: -100, elapsed: 0.1, duration: 7200), -fast)
    }

    func testOneTouchGestureCannotTraverseTheWholeFilm() {
        XCTAssertEqual(NTVScrubMotion.position(proposed: 7000, anchor: 120, duration: 7200), 210)
        XCTAssertEqual(NTVScrubMotion.position(proposed: -7000, anchor: 120, duration: 7200), 30)
        XCTAssertEqual(NTVScrubMotion.position(proposed: 90, anchor: 10, duration: 90), 19)
        XCTAssertEqual(NTVScrubMotion.position(proposed: .nan, anchor: 10, duration: 90), 0)
    }

    func testTouchScrubRejectsUnknownDurationAndInvalidSamples() {
        XCTAssertEqual(NTVScrubMotion.delta(points: 100, elapsed: 0.1, duration: 0), 0)
        XCTAssertEqual(NTVScrubMotion.delta(points: .nan, elapsed: 0.1, duration: 7200), 0)
        XCTAssertEqual(NTVScrubMotion.delta(points: 100, elapsed: 0, duration: 7200), 0)
        XCTAssertTrue(NTVScrubMotion.delta(points: .greatestFiniteMagnitude, elapsed: 0.001, duration: .greatestFiniteMagnitude).isFinite)
    }

    func testOldProfileDecodePreservesSettings() throws {
        let data = Data(##"{"id":3,"name":"Invité","avatarColorHex":"#123456","avatarURL":"https://example.invalid/old.png","pinEnabled":true}"##.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(profile.id, 3)
        XCTAssertEqual(profile.avatarColorHex, "#123456")
        XCTAssertTrue(profile.pinEnabled)
        XCTAssertNil(profile.localAvatarID)
        XCTAssertEqual(profile.avatarURL, "https://example.invalid/old.png")
    }

    @MainActor
    func testLocalAvatarPersistsAndSurvivesRemoteSync() throws {
        let defaults = UserDefaults.standard
        let keys = ["orivio.profiles.v1", "orivio.profiles.active"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let old = UserProfile(id: 1, name: "Nicolas", avatarColorHex: "#123456",
                              avatarID: "old", avatarURL: "https://example.invalid/old.png")
        defaults.set(try JSONEncoder().encode([old]), forKey: keys[0])
        defaults.set(1, forKey: keys[1])
        let store = ProfileStore()
        var pushes = 0
        store.onLocalChange = { pushes += 1 }
        store.setLocalAvatar(id: 1, avatar: .curls)
        XCTAssertEqual(pushes, 0, "A bundled avatar should not alter the account's remote avatar.")
        XCTAssertEqual(ProfileStore().active.localAvatarID, NTVProfileAvatar.curls.id)
        store.replaceRemote([UserProfile(id: 1, name: "Nicolas", avatarColorHex: "#654321")])
        XCTAssertEqual(store.active.localAvatarID, NTVProfileAvatar.curls.id)
        XCTAssertEqual(store.active.avatarColorHex, "#654321")
        XCTAssertNil(store.avatarURL(for: store.active))
        store.setAvatar(id: 1, avatarID: nil)
        XCTAssertNil(ProfileStore().active.localAvatarID)
        XCTAssertNil(store.active.avatarURL)
        XCTAssertNil(store.avatarURL(for: store.active))
        XCTAssertEqual(pushes, 1)
    }

    func testTVDoesNotBecomeMovieOrSeriesHomeRow() throws {
        let tv = try catalog(type: "tv")
        XCTAssertFalse(tv.appearsOnHome)
        XCTAssertTrue(tv.supportsSkip)
        XCTAssertEqual(tv.genreOptions, ["Sports", "Films"])
        XCTAssertTrue(try catalog(type: "movie").appearsOnHome)
        XCTAssertTrue(try catalog(type: "series").appearsOnHome)
    }

    @MainActor
    func testTVPaginationDeduplicatesAndStopsRepeatedPages() async throws {
        let addon = try fixtureAddon()
        let viewModel = LiveTVViewModel { _, _, _, skip in
            let ids = skip == nil ? ["a", "b"] : ["b", "c"]
            return ids.map { MetaItem(id: $0, type: "tv", name: $0) }
        }
        await viewModel.load(addons: [addon])
        let sectionID = try XCTUnwrap(viewModel.sections.first?.id)
        XCTAssertTrue(viewModel.sections[0].canLoadMore)
        await viewModel.loadMore(sectionID: sectionID)
        XCTAssertEqual(viewModel.sections[0].channels.map(\.id), ["a", "b", "c"])
        await viewModel.loadMore(sectionID: sectionID)
        XCTAssertFalse(viewModel.sections[0].canLoadMore)
        XCTAssertEqual(viewModel.sections[0].channels.count, 3)
        XCTAssertFalse(viewModel.sections[0].loadingMore)
    }

    @MainActor
    func testNewTVCategoryWinsOverLatePreviousRequest() async throws {
        let addon = try fixtureAddon()
        let gate = TVCategoryTestGate()
        let viewModel = LiveTVViewModel { _, _, genre, _ in
            await gate.started(genre)
            try await Task.sleep(nanoseconds: genre == nil ? 150_000_000 : 10_000_000)
            return [MetaItem(id: genre ?? "old", type: "tv", name: genre ?? "old")]
        }
        let old = Task { await viewModel.load(addons: [addon]) }
        while !(await gate.oldRequestStarted) { await Task.yield() }
        viewModel.selectedGenre = "Sports"
        await viewModel.load(addons: [addon])
        await old.value
        XCTAssertEqual(viewModel.sections.first?.channels.first?.id, "Sports")
        XCTAssertEqual(viewModel.selectedGenre, "Sports")
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testTVPaginationCanRetryAfterNetworkFailure() async throws {
        let addon = try fixtureAddon()
        let fixture = TVPageRetryFixture()
        let viewModel = LiveTVViewModel { _, _, _, skip in try await fixture.page(skip: skip) }
        await viewModel.load(addons: [addon])
        let sectionID = try XCTUnwrap(viewModel.sections.first?.id)
        await viewModel.loadMore(sectionID: sectionID)
        XCTAssertEqual(viewModel.sections[0].channels.map(\.id), ["a"])
        XCTAssertNotNil(viewModel.sections[0].loadError)
        XCTAssertFalse(viewModel.sections[0].loadingMore)
        XCTAssertTrue(viewModel.sections[0].canLoadMore)
        await viewModel.loadMore(sectionID: sectionID)
        XCTAssertEqual(viewModel.sections[0].channels.map(\.id), ["a", "b"])
        XCTAssertNil(viewModel.sections[0].loadError)
        let offsets = await fixture.offsets
        XCTAssertEqual(offsets, [1, 1], "Retry must request the failed page, without skipping channels.")
    }

    private func catalog(type: String) throws -> ManifestCatalog {
        let data = Data("{\"type\":\"\(type)\",\"id\":\"channels\",\"extra\":[{\"name\":\"genre\",\"options\":[\"Sports\",\"Films\"]},{\"name\":\"skip\"}]}".utf8)
        return try JSONDecoder().decode(ManifestCatalog.self, from: data)
    }
    private func fixtureAddon() throws -> InstalledAddon {
        let data = Data(#"{"id":"ntv.test.tv","name":"Test TV","version":"1","types":["tv"],"resources":["catalog"],"catalogs":[{"type":"tv","id":"channels","extra":[{"name":"genre","options":["Sports","Films"]},{"name":"skip"}]}]}"#.utf8)
        return InstalledAddon(manifestURL: "https://example.invalid/manifest.json",
                              manifest: try JSONDecoder().decode(AddonManifest.self, from: data))
    }
}

private actor TVCategoryTestGate {
    private(set) var oldRequestStarted = false
    func started(_ genre: String?) { if genre == nil { oldRequestStarted = true } }
}

private actor CatalogPreviewFixture {
    private(set) var calls = 0
    func page() -> [MetaItem] {
        calls += 1
        return (0..<200).flatMap { index in
            [MetaItem(id: String(index), type: "movie", name: "Fixture"), MetaItem(id: String(index), type: "movie", name: "Duplicate")]
        }
    }
}
private actor TVPageRetryFixture {
    private(set) var offsets: [Int] = []
    func page(skip: Int?) throws -> [MetaItem] {
        guard let skip else { return [MetaItem(id: "a", type: "tv", name: "A")] }
        offsets.append(skip)
        if offsets.count == 1 { throw URLError(.notConnectedToInternet) }
        return [MetaItem(id: "b", type: "tv", name: "B")]
    }
}


@MainActor
final class NTVPlayerComfortTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ntv.player.comfort.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private func row(_ id: String = "film") -> WatchProgress {
        WatchProgress(id: id, metaID: id, type: "movie", name: "Film", poster: nil,
            background: nil, logo: nil, season: nil, episode: nil, episodeTitle: nil,
            positionSeconds: 180, durationSeconds: 3600, updatedAt: now)
    }
    func testOnlyANewProcessCanClaimAnInterruptedPlayback() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults)
            live.record(id: "film", profile: 1, session: UUID(), position: 180, duration: 3600, now: now)
            XCTAssertNil(live.claim(profile: 1, items: [row()], now: now), "Returning from PiP or changing tabs is not a crash.")
            let relaunched = NTVResumeSuggestion(defaults: defaults)
            XCTAssertNil(relaunched.claim(profile: 1, items: [], now: now))
            XCTAssertEqual(relaunched.claim(profile: 1, items: [row()], now: now)?.id, "film")
            XCTAssertNil(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row()], now: now))
        }
    }
    func testVoluntaryExitDoesNotSuggestResumeOnRelaunch() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults), session = UUID()
            live.record(id: "film", profile: 1, session: session, position: 180, duration: 3600, now: now)
            live.clear(profile: 1, session: session)
            XCTAssertNil(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row()], now: now))
        }
    }
    func testLateTeardownCannotClearTheReplacementPlayersMarker() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults), old = UUID(), replacement = UUID()
            live.record(id: "old", profile: 1, session: old, position: 180, duration: 3600, now: now)
            live.record(id: "new", profile: 1, session: replacement, position: 180, duration: 3600, now: now)
            live.clear(profile: 1, session: old)
            XCTAssertEqual(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row("new")], now: now)?.id, "new")
        }
    }
    func testResumePreferencesAndInterruptionMarkersAreProfileScoped() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults)
            live.setMode(.off, profile: 1)
            live.setMode(.latest, profile: 2)
            live.record(id: "film", profile: 1, session: UUID(), position: 180, duration: 3600, now: now)
            let relaunched = NTVResumeSuggestion(defaults: defaults)
            XCTAssertEqual(relaunched.mode(profile: 1), .off)
            XCTAssertEqual(relaunched.mode(profile: 2), .latest)
            XCTAssertEqual(relaunched.mode(profile: 3), .interrupted)
            XCTAssertNil(relaunched.claim(profile: 1, items: [row()], now: now))
            XCTAssertNotNil(relaunched.claim(profile: 2, items: [row()], now: now))
            relaunched.purge(profile: 2)
            XCTAssertEqual(relaunched.mode(profile: 2), .interrupted)
        }
    }
    func testFinishedContentCannotBecomeAnInterruptionOffer() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults), session = UUID()
            live.record(id: "film", profile: 1, session: session, position: 180, duration: 3600, now: now)
            live.record(id: "film", profile: 1, session: session, position: 3590, duration: 3600, now: now)
            XCTAssertNil(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row()], now: now))
        }
    }
    func testInterruptionMarkersHaveNoRawIdentifiersAndDoNotInvalidateHomeOnSave() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults), id = "https://example.invalid/private/fixture"
            live.record(id: id, profile: 1, session: UUID(), position: 180, duration: 3600, now: now)
            let data = try XCTUnwrap(defaults.data(forKey: ProfileScopedDefaults.key("ntv.resume.marker.v2", 1)))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(id))
            XCTAssertEqual(live.revision, 0, "Periodic progress must not invalidate the Home prompt subtree.")
            XCTAssertEqual(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row(id)], now: now)?.id, id)
        }
    }
    func testExpiredOrFinishedSavedRowsDoNotConsumeAnUnrelatedOffer() throws {
        try withDefaults { defaults in
            let live = NTVResumeSuggestion(defaults: defaults)
            live.record(id: "film", profile: 1, session: UUID(), position: 180, duration: 3600, now: now.addingTimeInterval(-31 * 86400))
            XCTAssertNil(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row()], now: now))
            defaults.set(Data(repeating: 0, count: 1025), forKey: ProfileScopedDefaults.key("ntv.resume.marker.v2", 1))
            XCTAssertNil(NTVResumeSuggestion(defaults: defaults).claim(profile: 1, items: [row()], now: now))
        }
    }
    func testTransportStaysVisibleAcrossEveryBusyOrPausedState() {
        XCTAssertTrue(NTVTransportIdlePolicy.canHide(playing: true, buffering: false, switching: false, scrubbing: false, seeking: false))
        for flags in [(false,false,false,false,false),(true,true,false,false,false),
                      (true,false,true,false,false),(true,false,false,true,false),(true,false,false,false,true)] {
            XCTAssertFalse(NTVTransportIdlePolicy.canHide(playing: flags.0, buffering: flags.1, switching: flags.2, scrubbing: flags.3, seeking: flags.4))
        }
    }
    func testTrackLanguageMetadataWinsOverAnAmbiguousLabel() {
        let options = [TrackOption(id: "one", displayName: "French commentary", payload: .off, languageCode: "eng"),
                       TrackOption(id: "two", displayName: "Français SDH", payload: .off)]
        let groups = NTVTrackLanguageGroup.build(options)
        XCTAssertEqual(groups.first { $0.id == "en" }?.options.map(\.id), ["one"])
        XCTAssertEqual(groups.first { $0.id == "fr" }?.options.map(\.id), ["two"])
    }
    func testSubtitleProviderNameCannotInventATrackLanguage() {
        let groups = NTVTrackLanguageGroup.build([
            TrackOption(id: "sub-off", displayName: "Off", payload: .off),
            TrackOption(id: "unknown", displayName: "Track 1 · French Provider", payload: .off),
            TrackOption(id: "fr", displayName: "fr · Provider", payload: .off),
            TrackOption(id: "fr-sdh", displayName: "French (SDH) · Provider", payload: .off)])
        XCTAssertEqual(groups.map(\.id), ["fr", "und"])
        XCTAssertEqual(groups.first?.options.map(\.id), ["fr", "fr-sdh"])
        XCTAssertEqual(groups.last?.options.map(\.id), ["unknown"])
    }
    func testArrivingTracksRetainLanguageAndTrackIdentities() {
        let french = TrackOption(id: "fr", displayName: "French", payload: .off)
        let before = NTVTrackLanguageGroup.build([french])
        let after = NTVTrackLanguageGroup.build([TrackOption(id: "en", displayName: "English", payload: .off), french])
        XCTAssertEqual(before.first?.id, after.first { $0.id == "fr" }?.id)
        XCTAssertEqual(before.first?.options.map(\.id), after.first { $0.id == "fr" }?.options.map(\.id))
    }
    func testNewSeasonIsDifferentFromBackCatalogueAndFutureEpisodes() {
        func ep(_ season: Int, _ episode: Int, _ date: String) -> MetaVideo {
            MetaVideo(id: "\(season):\(episode)", title: nil, season: season, episode: episode, released: date)
        }
        let started = ReleaseDateParser.parse("2025-01-01")!, today = ReleaseDateParser.parse("2025-06-01")!
        let episodes = [ep(1,1,"2024-01-01"), ep(1,2,"2024-02-01"), ep(2,1,"2025-05-01"),
                        ep(2,1,"2025-05-01"), ep(2,2,"2025-07-01")]
        let result = NTVEpisodeReleaseStatus.resolve(episodes: episodes, startedAt: started,
            reached: [SeasonEpisode(season: 1, episode: 1)], now: today)
        XCTAssertEqual(result, NTVEpisodeReleaseStatus(count: 1, newSeason: 2), "Do not count duplicate specials, back catalogue or future episodes.")
        XCTAssertEqual(result.label, "Nouvelle saison · S2")
    }
    func testFutureWatchedMarkersDoNotHideActuallyNewEpisodes() {
        let first = MetaVideo(id: "1", title: nil, season: 1, episode: 1, released: "2024-01-01")
        let next = MetaVideo(id: "2", title: nil, season: 1, episode: 2, released: "2025-05-01")
        let future = MetaVideo(id: "3", title: nil, season: 1, episode: 3, released: "2028-01-01")
        let result = NTVEpisodeReleaseStatus.resolve(episodes: [first,next,future], startedAt: ReleaseDateParser.parse("2025-01-01"),
            reached: [SeasonEpisode(season: 1, episode: 1), SeasonEpisode(season: 1, episode: 3)],
            now: ReleaseDateParser.parse("2025-06-01")!)
        XCTAssertEqual(result, NTVEpisodeReleaseStatus(count: 1, newSeason: nil))
        XCTAssertEqual(result.label, "Nouvel épisode")
    }
    func testUnknownAirDatesOrHistoryDoNotInventReleaseBadges() {
        let unknown = MetaVideo(id: "unknown", title: nil, season: 2, episode: 1)
        XCTAssertEqual(NTVEpisodeReleaseStatus.resolve(episodes: [unknown], startedAt: now,
            reached: [SeasonEpisode(season: 1, episode: 1)], now: now), .none)
        XCTAssertEqual(NTVEpisodeReleaseStatus.resolve(episodes: [], startedAt: nil, reached: [], now: now), .none)
    }
    func testAbsoluteEpisodeDisplayRequiresExplicitMetadataAndRoundTrips() throws {
        let base = MetaVideo(id: "anime", title: nil, season: 2, episode: 2, originalEpisode: 26)
        XCTAssertEqual(base.displayEpisodeCode, "S2:E2", "Linked-special numbering is not an absolute anime number.")
        let data = Data(#"{"id":"anime","season":2,"episode":2,"absolute_number":26}"#.utf8)
        let explicit = try JSONDecoder().decode(MetaVideo.self, from: data)
        XCTAssertEqual(explicit.displayEpisodeCode, "S2:E2 · Ép. 26")
        XCTAssertEqual(try JSONDecoder().decode(MetaVideo.self, from: JSONEncoder().encode(explicit)).absoluteEpisode, 26)
        XCTAssertNil(MetaVideo(id: "bad", title: nil, season: 2, episode: 2, absoluteEpisode: -1).absoluteEpisode)
    }
}
