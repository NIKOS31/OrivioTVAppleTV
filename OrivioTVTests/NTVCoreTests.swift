import XCTest
@testable import OrivioTV

final class NTVCoreTests: XCTestCase {
    func testOldProfileDecodePreservesSettings() throws {
        let data = Data(#"{"id":3,"name":"Invité","avatarColorHex":"#123456","avatarURL":"https://example.invalid/old.png","pinEnabled":true}"#.utf8)
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
        let viewModel = LiveTVViewModel { _, _, genre, _ in
            try await Task.sleep(nanoseconds: genre == nil ? 150_000_000 : 10_000_000)
            return [MetaItem(id: genre ?? "old", type: "tv", name: genre ?? "old")]
        }
        let old = Task { await viewModel.load(addons: [addon]) }
        await Task.yield()
        viewModel.selectedGenre = "Sports"
        await viewModel.load(addons: [addon])
        await old.value
        XCTAssertEqual(viewModel.sections.first?.channels.first?.id, "Sports")
        XCTAssertEqual(viewModel.selectedGenre, "Sports")
        XCTAssertFalse(viewModel.isLoading)
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
