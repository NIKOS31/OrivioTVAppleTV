import XCTest
import UIKit
@testable import OrivioTV

final class NTVCoreTests: XCTestCase {
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
    func testCompiledAppSupportsTheSystemIconAPI() async throws {
        let app = UIApplication.shared
        XCTAssertTrue(app.supportsAlternateIcons,
                      "Recognizing plist entries alone must not mask a declaration UIKit cannot use.")
        for _ in 0..<50 where app.applicationState != .active {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(app.applicationState, .active, "Icon registration must be tested in the active host app.")
        guard app.applicationState == .active else { return }
        try await app.setAlternateIconName("NTVSystemIcon")
        XCTAssertEqual(app.alternateIconName, "NTVSystemIcon",
                       "The actual UIKit registration must finish with the supplied n selected, not just a true capability flag.")
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
        XCTAssertEqual(model.meta.name, "Enriched", "Metadata enrichment remains available.")
    }

    @MainActor
    func testDetailFallbackArtworkDoesNotSwitchFromPosterToBackdrop() {
        let model = DetailViewModel(item: MetaItem(id: "fixture", type: "movie", name: "Opening", poster: "https://example.invalid/poster.jpg"))
        model.meta = MetaItem(id: "fixture", type: "movie", name: "Enriched", background: "https://example.invalid/late.jpg", logo: "https://example.invalid/late-logo.png")
        XCTAssertEqual(model.openingBackground, "https://example.invalid/poster.jpg")
        XCTAssertNil(model.openingLogo)
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
