import XCTest
@testable import OrivioTV

final class NTVCoreTests: XCTestCase {
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
private actor TVPageRetryFixture {
    private(set) var offsets: [Int] = []
    func page(skip: Int?) throws -> [MetaItem] {
        guard let skip else { return [MetaItem(id: "a", type: "tv", name: "A")] }
        offsets.append(skip)
        if offsets.count == 1 { throw URLError(.notConnectedToInternet) }
        return [MetaItem(id: "b", type: "tv", name: "B")]
    }
}
