import XCTest
@testable import OrivioTV

/// Controlled payloads and actual HTTP exercise the production boundary.
final class NTVAddonPayloadTests: XCTestCase {
    private var addonSource: URL { URL(string: "https://addon.invalid/config/manifest.json")! }

    private func checked(_ object: Any, resource: NTVAddonPayloadPolicy.Resource, source: URL? = nil) throws -> Data {
        try NTVAddonPayloadPolicy.checkedData(JSONSerialization.data(withJSONObject: object), resource: resource, source: source ?? addonSource)
    }

    func testManifestSecurityKeepsSupportedShapesAndCosmeticTolerance() throws {
        let raw: [String: Any] = ["id": "org.ntv.fixture", "version": 2, "types": ["movie", "series", "tv"],
            "resources": ["catalog", ["name": "stream", "types": ["movie"], "idPrefixes": ["tt", "tmdb:"]]] as [Any],
            "catalogs": [["id": "popular", "type": "movie", "extra": [["name": "genre", "options": ["Action & Adventure", "Drame"]]]],
                         ["id": "popular", "type": "series"]]]
        let data = try checked(raw, resource: .manifest)
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: data)
        XCTAssertEqual(manifest.name, "org.ntv.fixture", "Missing display names remain cosmetic.")
        XCTAssertEqual(manifest.version, "2.0")
        XCTAssertTrue(manifest.providesStreams)
        XCTAssertEqual(manifest.catalogs?.count, 2)
    }

    func testManifestSecurityRejectsMalformedRoutingFieldsWithoutEchoingInput() {
        let cases: [[String: Any]] = [
            ["id": "PRIVATE-SENTINEL", "resources": "stream"],
            ["id": "org.ntv.fixture", "resources": [NSNull()]],
            ["id": "org.ntv.fixture", "resources": [["name": "stream", "types": [3]]]],
            ["id": "org.ntv.fixture", "types": ["movie\nPRIVATE-SENTINEL"]],
            ["id": "org.ntv.fixture", "catalogs": [["id": "..", "type": "movie"]]],
            ["id": "org.ntv.fixture", "catalogs": [["id": "a", "type": "movie"], ["id": "a", "type": "movie"]]],
            ["id": "org.ntv.fixture", "catalogs": [3]], ["name": "Missing ID"]]
        for raw in cases {
            XCTAssertThrowsError(try checked(raw, resource: .manifest)) { error in
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE-SENTINEL"))
                XCTAssertFalse(NTVAddonDiagnostics.failure(error).contains("PRIVATE-SENTINEL"))
            }
        }
    }

    func testManifestSecurityBoundsCatalogsAndFilterOptionsBeforeLossyDecoding() {
        let catalogs = (0..<129).map { ["id": "catalog-\($0)", "type": "movie"] }
        XCTAssertThrowsError(try checked(["id": "fixture", "catalogs": catalogs], resource: .manifest)) {
            guard case StremioAPIError.responseTooLarge = $0 else { return XCTFail("Expected collection limit") }
        }
        let catalog: [String: Any] = ["id": "a", "type": "movie", "extra": [["name": "genre", "options": Array(repeating: "Drama", count: 2_049)]]]
        XCTAssertThrowsError(try checked(["id": "fixture", "catalogs": [catalog]], resource: .manifest))
        XCTAssertThrowsError(try checked(["id": "fixture", "resources": Array(repeating: "stream", count: 17)], resource: .manifest))
    }

    func testResourcePathEncodingCannotCreateAQueryOrFragment() throws {
        let text = "tmdb:12/a?token=PRIVATE-SENTINEL#x%2F"
        let encoded = try NTVAddonPayloadPolicy.pathComponent(text)
        let url = try XCTUnwrap(URL(string: "https://addon.invalid/meta/movie/\(encoded).json"))
        XCTAssertNil(url.query); XCTAssertNil(url.fragment)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.split(separator: "/").count, 3)
        XCTAssertTrue(encoded.contains("%2F")); XCTAssertTrue(encoded.contains("%25"))
        for raw in ["", ".", "..", "movie\r\n", String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try NTVAddonPayloadPolicy.pathComponent(raw))
        }
    }

    func testInternetAddonCannotSupplyLiteralPrivateOrAliasDestinations() {
        for host in ["127.0.0.1", "127.1", "2130706433", "0x7f000001", "0177.0.0.1", "10.0.0.1", "172.16.1.1", "192.168.1.1",
                     "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "localhost.", "localhost..", "127.0.0.1..", "box.local", "box.local..", "printer",
                     "[::1]", "[::]", "[::ffff:127.0.0.1]", "[::ffff:192.168.1.1]", "[fe80::1]", "[fd00::1]", "[64:ff9b::7f00:1]"] {
            XCTAssertFalse(NTVAddonLinkPolicy.permits("http://\(host)/private", source: addonSource), host)
        }
    }

    func testConfiguredLANAddonKeepsOnlyItsOwnLocalService() throws {
        let source = try XCTUnwrap(URL(string: "http://192.168.1.2:8099/config/manifest.json"))
        XCTAssertTrue(NTVAddonLinkPolicy.permits("http://192.168.1.2:8099/video.m3u8", source: source))
        XCTAssertFalse(NTVAddonLinkPolicy.permits("http://192.168.1.3:8099/video.m3u8", source: source))
        XCTAssertFalse(NTVAddonLinkPolicy.permits("http://192.168.1.2:80/private", source: source))
        XCTAssertFalse(NTVAddonLinkPolicy.permits("http://127.0.0.1:8099/private", source: source))
        XCTAssertTrue(NTVAddonLinkPolicy.permits("https://cdn.invalid/video.m3u8", source: source))
        let secure = try XCTUnwrap(URL(string: "https://box.local/manifest.json"))
        XCTAssertFalse(NTVAddonLinkPolicy.permits("http://box.local/private", source: secure))
    }

    func testSecondaryLinksKeepPublicURLsAndRejectCredentialsAndSchemes() {
        for raw in ["https://cdn.invalid/video.m3u8?token=PRIVATE-SENTINEL", "https://8.8.8.8/artwork.jpg", "https://[2606:4700:4700::1111]/artwork.jpg"] {
            XCTAssertTrue(NTVAddonLinkPolicy.permits(raw, source: addonSource))
        }
        for raw in ["file:///private/data", "javascript:alert(1)", "data:video/mp4,abc", "vlc://video", "https://user:PRIVATE-SENTINEL@cdn.invalid/movie", "https://cdn.invalid:0/movie"] {
            XCTAssertFalse(NTVAddonLinkPolicy.permits(raw, source: addonSource))
        }
    }

    func testMixedSourcesKeepGoodStreamsAndTorrentsWhileDroppingUnsafeLinks() throws {
        let torrent = String(repeating: "a", count: 40)
        let raw: [String: Any] = ["streams": [
            ["url": "https://cdn.invalid/movie.m3u8", "name": "Valid", "behaviorHints": ["proxyHeaders": ["request": ["User-Agent": "nTV fixture", "Host": "internal", "X-Test": "x\r\nPRIVATE-SENTINEL"]]]],
            ["url": "file:///private/data"], ["externalUrl": "javascript:alert(1)"], ["url": "http://127.0.0.1/private"],
            ["infoHash": torrent, "fileIdx": 0], ["infoHash": "bad"]] as [[String: Any]]]
        let response = try JSONDecoder().decode(StreamsResponse.self, from: checked(raw, resource: .streams))
        let streams = try XCTUnwrap(response.streams)
        XCTAssertEqual(streams.count, 2)
        XCTAssertTrue(streams[0].isPlayable); XCTAssertTrue(streams[1].isTorrent)
        XCTAssertEqual(streams[0].behaviorHints?.proxyHeaders?.requestHeaders, ["User-Agent": "nTV fixture"])
    }

    func testSourceHeaderBudgetsDoNotForwardRoutingOrOversizedHeaders() throws {
        let raw: [String: Any] = ["streams": [["url": "https://cdn.invalid/a", "behaviorHints": ["proxyHeaders": ["request": ["Referer": String(repeating: "x", count: 17_000)]]]]]]
        let result = try JSONDecoder().decode(StreamsResponse.self, from: checked(raw, resource: .streams))
        XCTAssertNil(result.streams?.first?.behaviorHints?.proxyHeaders?.requestHeaders)
    }

    func testCatalogArtworkAndEpisodeThumbnailsCannotPointAtLocalFilesOrLAN() throws {
        let raw: [String: Any] = ["metas": [["id": "tt123", "type": "movie", "name": "Fixture", "poster": "file:///private/a", "posterFallback": "http://169.254.169.254/keys", "background": "https://cdn.invalid/a.jpg", "videos": [["id": "tt123:1:1", "thumbnail": "http://box.local/a.jpg"]]], ["id": "..", "name": "Invalid"]]]
        let response = try JSONDecoder().decode(CatalogResponse.self, from: checked(raw, resource: .catalog))
        let item = try XCTUnwrap(response.metas?.first)
        XCTAssertEqual(response.metas?.count, 1); XCTAssertNil(item.poster); XCTAssertNil(item.posterFallback)
        XCTAssertEqual(item.background, "https://cdn.invalid/a.jpg")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: checked(raw, resource: .catalog)) as? [String: Any])
        let meta = try XCTUnwrap((object["metas"] as? [[String: Any]])?.first)
        XCTAssertNil((meta["videos"] as? [[String: Any]])?.first?["thumbnail"])
    }

    func testSubtitleLinksUseTheSameDestinationPolicy() throws {
        let raw: [String: Any] = ["subtitles": [["url": "https://cdn.invalid/fr.srt", "lang": "fra"], ["url": "file:///private/passwd"], ["url": "http://192.168.1.1/private"]]]
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: checked(raw, resource: .subtitles)) as? [String: Any])
        XCTAssertEqual((object["subtitles"] as? [[String: Any]])?.count, 1)
    }

    func testCollectionLimitsCountMalformedEntriesBeforeLossyDecode() {
        for (resource, key, count) in [(NTVAddonPayloadPolicy.Resource.streams, "streams", 4_097), (.catalog, "metas", 1_001), (.subtitles, "subtitles", 257)] {
            XCTAssertThrowsError(try checked([key: Array(repeating: NSNull(), count: count)], resource: resource)) {
                guard case StremioAPIError.responseTooLarge = $0 else { return XCTFail("Expected collection bound") }
            }
        }
    }

    func testMetadataEpisodeListIsBounded() {
        let raw: [String: Any] = ["meta": ["id": "tt123", "name": "Fixture", "videos": Array(repeating: ["id": "a"], count: 5_001)]]
        XCTAssertThrowsError(try checked(raw, resource: .meta))
    }

    func testJSONNestingIsBoundedButQuotedBracesAreJustText() throws {
        let deep = Data(("{\"unused\":" + String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33) + "}").utf8)
        XCTAssertThrowsError(try NTVAddonPayloadPolicy.checkedData(deep, resource: .catalog, source: addonSource))
        let raw: [String: Any] = ["id": "fixture", "description": String(repeating: "[\\\"{", count: 100)]
        XCTAssertNoThrow(try checked(raw, resource: .manifest))
    }

    func testInvalidManifestIsNeverRetainedInTheResponseCache() async throws {
        let server = try NTVAddonHTTPFixture(bodies: [#"{"id":"fixture","resources":"stream"}"#, #"{"id":"fixture","resources":["stream"],"catalogs":[]}"#])
        defer { server.stop() }
        let url = try await server.start()
        do { _ = try await StremioAPI.manifest(url: url.absoluteString); XCTFail("Invalid routing must fail before cache storage") }
        catch { guard case StremioAPIError.invalidResponse = error else { return XCTFail("Expected schema failure") } }
        let manifest = try await StremioAPI.manifest(url: url.absoluteString)
        XCTAssertTrue(manifest.providesStreams); XCTAssertEqual(server.requests.count, 2)
        _ = try await StremioAPI.manifest(url: url.absoluteString)
        XCTAssertEqual(server.requests.count, 2, "Only the good, checked manifest is cached.")
    }

    func testStremioStreamAPIUsesPayloadChecksBeforeReturningSources() async throws {
        let server = try NTVAddonHTTPFixture(bodies: [#"{"streams":[{"url":"https://cdn.invalid/a.m3u8"},{"url":"file:///private/data"}]}"#])
        defer { server.stop() }
        let url = try await server.start()
        let addon = InstalledAddon(manifestURL: url.absoluteString, manifest: .placeholder(manifestURL: url.absoluteString))
        let sources = try await StremioAPI.streams(addon: addon, type: "movie", id: "tt123")
        XCTAssertEqual(sources.count, 1); XCTAssertEqual(sources.first?.url, "https://cdn.invalid/a.m3u8")
        XCTAssertEqual(server.requests.count, 1)
    }

    @MainActor
    func testAddonSyncFailureDoesNotExposeTheProvidersPrivateError() async {
        let sentinel = "PRIVATE-SYNC-SENTINEL"
        let manager = AddonManager(startRefresh: false, manifestLoader: { _ in throw URLError(.notConnectedToInternet) })
        manager.onSyncRequested = {
            throw NSError(domain: sentinel, code: 42, userInfo: [NSLocalizedDescriptionKey:
                "https://addon.invalid/\(sentinel)/manifest.json?key=\(sentinel)"])
        }
        let outcome = await manager.syncWithAccount()
        guard case .failed(let reason) = outcome else { return XCTFail("Expected controlled sync failure") }
        XCTAssertEqual(reason, "le service n’a pas pu terminer la demande")
        XCTAssertFalse(outcome.message.contains(sentinel))
        XCTAssertFalse(outcome.message.contains("addon.invalid"))
    }
}
