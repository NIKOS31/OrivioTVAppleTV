import XCTest
import AVFoundation
@testable import OrivioTV

final class NTVTwitchTests: XCTestCase {
    func testNativePlaybackUsesOnlyAnonymousVideoRequests() async throws {
        let fixture = NTVTwitchPlaybackFixture()
        let api = NTVTwitchPlayback(transport: { try await fixture.send($0, $1) }, now: { Date(timeIntervalSince1970: 1000) })
        let url = try await api.resolve(channel: "FIXTURE_CHANNEL")
        XCTAssertEqual(url.host, "usher.ttvnw.net")
        XCTAssertEqual(url.path, "/api/v2/channel/hls/fixture_channel.m3u8")
        let requests = await fixture.recorded()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Client-Integrity"))
        }
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Client-ID"), "Video-CDN requests need no account/app credentials")
    }

    func testDeniedExpiredAndWrongChannelVideoTicketsNeverReachThePlaylist() async throws {
        for mode in [NTVTwitchPlaybackFixture.Mode.denied, .expired, .wrongChannel] {
            let fixture = NTVTwitchPlaybackFixture(mode)
            let api = NTVTwitchPlayback(transport: { try await fixture.send($0, $1) }, now: { Date(timeIntervalSince1970: 1000) })
            do { _ = try await api.resolve(channel: "fixture_channel"); XCTFail("Invalid access cannot open video") }
            catch { XCTAssertTrue(error is NTVTwitchPlayback.Failure) }
            let sent = await fixture.recorded()
            XCTAssertEqual(sent.count, 1)
        }
    }

    func testInvalidPlaybackChannelCannotSendARequest() async throws {
        let fixture = NTVTwitchPlaybackFixture()
        let api = NTVTwitchPlayback(transport: { try await fixture.send($0, $1) })
        for invalid in ["", "../private", "https://example.invalid", "name?token=private", String(repeating: "a", count: 26)] {
            do { _ = try await api.resolve(channel: invalid); XCTFail("Invalid channel") }
            catch NTVTwitchPlayback.Failure.invalidChannel {}
        }
        let sent = await fixture.recorded()
        XCTAssertTrue(sent.isEmpty)
    }

    func testNativePlaybackFailuresNeverExposeServerContent() async throws {
        for status in [401, 403, 404, 429, 500] {
            let fixture = NTVTwitchPlaybackFixture(.http(status))
            let api = NTVTwitchPlayback(transport: { try await fixture.send($0, $1) })
            do { _ = try await api.resolve(channel: "fixture_channel"); XCTFail("Failed request") }
            catch { XCTAssertFalse(error.localizedDescription.contains("PRIVATE-VIDEO-ERROR-SENTINEL")) }
            let sent = await fixture.recorded()
            XCTAssertEqual(sent.count, 1, "No automatic account/cookie/integrity fallback")
        }
    }

    func testTwitchPlaylistRejectsUntrustedVariantsAndKeyOrigins() throws {
        let base = try XCTUnwrap(URL(string: "https://usher.ttvnw.net/live.m3u8"))
        for target in ["http://video.ttvnw.net/live.m3u8", "https://ttvnw.net.evil.invalid/live", "https://127.0.0.1/private", "file:///private", "https://user:secret@video.ttvnw.net/live"] {
            XCTAssertThrowsError(try NTVTwitchPlayback.validatePlaylist(Data("#EXTM3U\n\(target)\n".utf8), base: base))
            let keyed = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"\(target)\"\nhttps://video.ttvnw.net/valid.m3u8\n"
            XCTAssertThrowsError(try NTVTwitchPlayback.validatePlaylist(Data(keyed.utf8), base: base))
        }
        XCTAssertNoThrow(try NTVTwitchPlayback.validatePlaylist(Data("#EXTM3U\nhttps://video.ttvnw.net/live.m3u8\n".utf8), base: base))
    }

    @MainActor
    func testTwitchPlayerFailureDoesNotEchoSignedVideoURL() async {
        let sentinel = "PRIVATE-VIDEO-URL-SENTINEL"
        let model = NTVTwitchPlayerModel(resolve: { _ in
            throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://video.ttvnw.net/\(sentinel)"])
        })
        defer { model.stop() }
        await model.load(.init(login: "fixture_channel", name: "Fixture", title: "Fixture"))
        XCTAssertNotNil(model.message)
        XCTAssertFalse(model.message?.contains(sentinel) ?? true)
        XCTAssertNil(model.player)
    }

    @MainActor
    func testClosingTwitchPlayerRejectsALateVideoResponse() async {
        let started = expectation(description: "Video resolution started")
        let gate = NTVTwitchVideoGate(started: { started.fulfill() })
        let model = NTVTwitchPlayerModel(resolve: { _ in await gate.wait() })
        let pending = Task { await model.load(.init(login: "fixture_channel", name: "Fixture", title: "Fixture")) }
        await fulfillment(of: [started], timeout: 3)
        model.stop()
        await gate.finish(URL(fileURLWithPath: "/tmp/ntv-cancelled-video-fixture.mp4"))
        await pending.value
        XCTAssertNil(model.player, "Leaving/switching profile cannot resurrect a prior video")
        XCTAssertNil(model.message)
    }

    @MainActor
    func testTheMostRecentTwitchChannelWinsOverALateResponse() async {
        let started = expectation(description: "Old resolution started")
        let gate = NTVTwitchVideoGate(started: { started.fulfill() })
        let latest = URL(fileURLWithPath: "/tmp/ntv-latest-video-fixture.mp4")
        let model = NTVTwitchPlayerModel(resolve: { login in login == "old" ? await gate.wait() : latest })
        defer { model.stop() }
        let pending = Task { await model.load(.init(login: "old", name: "Old", title: "Old")) }
        await fulfillment(of: [started], timeout: 3)
        await model.load(.init(login: "latest", name: "Latest", title: "Latest"))
        await gate.finish(URL(fileURLWithPath: "/tmp/ntv-old-video-fixture.mp4"))
        await pending.value
        XCTAssertEqual((model.player?.currentItem?.asset as? AVURLAsset)?.url, latest)
    }

    private let tokenJSON = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":14400,"scope":["user:read:follows"],"token_type":"bearer"}"#
    private let identityJSON = #"{"client_id":"ntvtest","user_id":"42","login":"fixture","scopes":["user:read:follows"],"expires_in":14400}"#
    private let deviceJSON = #"{"device_code":"fixture-device","user_code":"ABCD","expires_in":1800,"interval":5,"verification_uri":"https://www.twitch.tv/activate?public=true&device-code=ABCD"}"#

    func testFailedCredentialDeletionStaysRevokedAcrossReload() throws {
        let suite = "ntv.twitch.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = TwitchSecretFixture()
        let credentials = NTVTwitchCredentials(clientID: "ntvtest", profileID: 1, defaults: defaults, secrets: secrets)
        let tokens = try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8))
        try credentials.save(tokens)
        secrets.failRemove = true
        XCTAssertThrowsError(try credentials.remove())
        XCTAssertFalse(secrets.values.isEmpty, "Simulate a Keychain item which physically remains.")
        let reopened = NTVTwitchCredentials(clientID: "ntvtest", profileID: 1, defaults: defaults, secrets: secrets)
        XCTAssertNil(try reopened.load(), "Reopening cannot restore a revoked session.")
        secrets.failWrite = true
        XCTAssertThrowsError(try reopened.save(tokens))
        XCTAssertNil(try reopened.load(), "Failed reconnect must not remove revocation.")
        secrets.failWrite = false
        try reopened.save(tokens)
        XCTAssertEqual(try reopened.load()?.accessToken, tokens.accessToken)
        let preferences = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(preferences.contains(tokens.accessToken))
        XCTAssertFalse(preferences.contains(tokens.refreshToken))
    }

    func testTwitchCredentialsSeparateProfilesAndAccountOwners() throws {
        let suite = "ntv.twitch.scope." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = TwitchSecretFixture()
        let a = NTVTwitchCredentials(clientID: "ntvtest", profileID: 1, ownerScope: "owner-A", defaults: defaults, secrets: secrets)
        let b = NTVTwitchCredentials(clientID: "ntvtest", profileID: 1, ownerScope: "owner-B", defaults: defaults, secrets: secrets)
        let otherProfile = NTVTwitchCredentials(clientID: "ntvtest", profileID: 2, ownerScope: "owner-A", defaults: defaults, secrets: secrets)
        let tokens = try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8))
        try a.save(tokens)
        XCTAssertNil(try b.load())
        XCTAssertNil(try otherProfile.load())
        try b.save(tokens)
        secrets.failRemove = true
        XCTAssertThrowsError(try a.remove())
        XCTAssertNil(try a.load())
        XCTAssertEqual(try b.load()?.accessToken, tokens.accessToken, "Retiring A must not revoke B.")
    }

    func testDisconnectAttemptsRemoteRevocationAfterLocalRemovalFailure() async throws {
        let tape = TwitchHTTPFixture([(200, identityJSON), (204, "")])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let tokens = try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8))
        let session = try NTVTwitchSession(api: api, storage: .init(load: { tokens }, save: { _ in },
            remove: { throw NTVTwitchError.secureStorage }))
        _ = try await session.validateSession()
        do { try await session.disconnect(); XCTFail("Storage failure must remain visible") }
        catch { XCTAssertEqual(error as? NTVTwitchError, .secureStorage) }
        let requests = await tape.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/oauth2/revoke" }.count, 1)
        do { _ = try await session.validateSession(); XCTFail("Memory session must be retired") }
        catch { XCTAssertEqual(error as? NTVTwitchError, .unauthorized) }
    }

    @MainActor func testLeavingTwitchDiscardsDelayedFollowedPage() async throws {
        let tape = TwitchHTTPFixture([(200, identityJSON), (200, streamsJSON(ids: ["late"], cursor: nil))], delay: 40_000_000)
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let tokens = try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8))
        let model = NTVTwitchViewModel(api: api, makeSession: { api, _, _ in
            try NTVTwitchSession(api: api, storage: .init(load: { tokens }, save: { _ in }, remove: {}))
        })
        await model.prepare(profileID: 1, ownerScope: "local")
        while await tape.requests.count < 2 { await Task.yield() }
        model.leave()
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertTrue(model.streams.isEmpty)
        XCTAssertNil(model.identity)
        XCTAssertFalse(model.loadingPage)
    }

    @MainActor func testFollowedPaginationDeduplicatesAndStopsRepeatedCursor() async throws {
        let tape = TwitchHTTPFixture([(200, identityJSON), (200, streamsJSON(ids: ["one"], cursor: "repeat")),
                                      (200, streamsJSON(ids: ["one", "two"], cursor: "repeat"))])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let tokens = try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8))
        let model = NTVTwitchViewModel(api: api, makeSession: { api, _, _ in
            try NTVTwitchSession(api: api, storage: .init(load: { tokens }, save: { _ in }, remove: {}))
        })
        await model.prepare(profileID: 1, ownerScope: "local")
        for _ in 0..<100 { if !model.loadingPage { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.streams.map(\.id), ["one"])
        XCTAssertEqual(model.followedCursor, "repeat")
        model.loadFollowed(append: true)
        for _ in 0..<100 { if !model.loadingPage { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.streams.map(\.id), ["one", "two"])
        XCTAssertNil(model.followedCursor)
        model.leave()
    }

    private func streamsJSON(ids: [String], cursor: String?) -> String {
        let data = ids.map { id -> [String: Any] in
            ["id": id, "user_id": "fixture", "user_login": "fixture", "user_name": "Fixture",
             "game_name": "Fixture", "title": "Fixture", "viewer_count": 1, "thumbnail_url": ""]
        }
        let pagination: [String: String] = cursor.map { ["cursor": $0] } ?? [:]
        return String(data: try! JSONSerialization.data(withJSONObject: ["data": data, "pagination": pagination]), encoding: .utf8)!
    }

    func testDeviceAuthorizationWaitsAndSlowsDownWithoutSecret() async throws {
        let tape = TwitchHTTPFixture([
            (200, deviceJSON), (400, #"{"message":"authorization_pending"}"#),
            (400, #"{"message":"slow_down"}"#), (200, tokenJSON), (200, identityJSON)
        ])
        let waits = TwitchWaitFixture()
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let flow = NTVTwitchAuthorization(api: api, sleep: { await waits.append($0) })
        let ticket = try await flow.begin()
        let result = try await flow.complete(ticket)
        XCTAssertEqual(result.1.userID, "42")
        let values = await waits.values
        XCTAssertEqual(values, [5_000_000_000, 5_000_000_000, 10_000_000_000])
        let requests = await tape.requests
        XCTAssertEqual(requests.first?.url?.host, "id.twitch.tv")
        for request in requests {
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(body.contains("client_secret"))
        }
    }

    func testExpiredOrCancelledDeviceFlowCannotObtainTokens() async throws {
        let tape = TwitchHTTPFixture([(200, deviceJSON)])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let flow = NTVTwitchAuthorization(api: api)
        let ticket = try await flow.begin()
        let expired = NTVTwitchAuthorization.Ticket(code: ticket.code, expiresAt: .distantPast)
        do { _ = try await flow.complete(expired); XCTFail("Expired code must not be polled") }
        catch { XCTAssertEqual(error as? NTVTwitchError, .expiredCode) }
        let cancelledFlow = NTVTwitchAuthorization(api: api, sleep: { _ in throw CancellationError() })
        do { _ = try await cancelledFlow.complete(ticket); XCTFail("Cancellation must stop polling") }
        catch { XCTAssertTrue(error is CancellationError) }
        let count = await tape.requests.count
        XCTAssertEqual(count, 1)
    }

    func testRefreshEncodesRestrictedCharactersWithoutSecret() async throws {
        let tape = TwitchHTTPFixture([(200, tokenJSON)])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        _ = try await api.refresh("value +/%&=")
        let request = await tape.requests.first!
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("refresh_token=value%20%2B%2F%25%26%3D"))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testDeviceCodeMustPointToOfficialHTTPSActivationPage() async throws {
        let tape = TwitchHTTPFixture([(200, deviceJSON.replacingOccurrences(of: "https://www.twitch.tv", with: "https://example.invalid"))])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        do { _ = try await api.beginDeviceAuthorization(); XCTFail("Activation must stay on the official Twitch site") }
        catch { XCTAssertEqual(error as? NTVTwitchError, .invalidResponse) }
    }

    func testWrongClientAndMissingFollowPermissionAreRejected() async throws {
        for response in [identityJSON.replacingOccurrences(of: "ntvtest", with: "anotherapp"),
                         identityJSON.replacingOccurrences(of: #"["user:read:follows"]"#, with: "[]")] {
            let tape = TwitchHTTPFixture([(200, response)])
            let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
            do { _ = try await api.validate("fixture-access"); XCTFail("Mismatched authorization must be rejected") }
            catch { XCTAssertEqual(error as? NTVTwitchError, .invalidIdentity) }
        }
    }

    func testFollowedAndSearchQueriesUseOfficialHelixAndCursor() async throws {
        let stream = #"{"data":[{"id":"1","user_id":"10","user_login":"streamer","user_name":"Streamer","game_name":"Jeu","title":"Direct","viewer_count":4,"thumbnail_url":"https://static-cdn.jtvnw.net/preview-{width}x{height}.jpg"}],"pagination":{"cursor":"next+page"}}"#
        let channels = #"{"data":[{"id":"10","broadcaster_login":"streamer","display_name":"Streamer","game_name":"Jeu","is_live":true,"thumbnail_url":"https://example.invalid/profile.png","title":"Direct"}],"pagination":{}}"#
        let tape = TwitchHTTPFixture([(200, stream), (200, channels)])
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let followed = try await api.followedStreams(accessToken: "fixture-access", userID: "42", after: "next+page")
        XCTAssertEqual(followed.data.first?.previewURL?.lastPathComponent, "preview-480x270.jpg")
        XCTAssertEqual(followed.pagination.cursor, "next+page")
        let search = try await api.searchChannels(" joueur & jeu ", accessToken: "fixture-access", liveOnly: true)
        XCTAssertTrue(search.data[0].isLive)
        let requests = await tape.requests
        XCTAssertEqual(requests[0].url?.path, "/helix/streams/followed")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Client-Id"), "ntvtest")
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query" }?.value, "joueur & jeu")
        XCTAssertEqual(query.first { $0.name == "live_only" }?.value, "true")
        for request in requests { XCTAssertEqual(request.url?.host, "api.twitch.tv") }
    }

    func testConcurrentUnauthorizedRequestsRefreshOnlyOnce() async throws {
        let tape = TwitchHTTPFixture([(401, "{}"), (200, tokenJSON), (200, identityJSON), (200, identityJSON)], delay: 30_000_000)
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let oldJSON = tokenJSON.replacingOccurrences(of: "test-access", with: "expired-access")
            .replacingOccurrences(of: "test-refresh", with: "previous-refresh")
        let storage = TwitchMemoryCredentials(try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(oldJSON.utf8)))
        let session = try NTVTwitchSession(api: api, storage: .init(load: { storage.tokens }, save: { storage.tokens = $0 }, remove: { storage.tokens = nil }))
        // Both callers enter validation before the first response returns.
        // Use two 401 replies, one refresh, then two successful validations.
        await tape.replace([(401, "{}"), (401, "{}"), (200, tokenJSON), (200, identityJSON), (200, identityJSON)])
        async let a = session.validateSession()
        async let b = session.validateSession()
        _ = try await (a, b)
        let requests = await tape.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/oauth2/token" }.count, 1)
        XCTAssertEqual(storage.tokens?.refreshToken, "test-refresh")
    }

    func testLateValidationCannotRestoreDisconnectedSession() async throws {
        let tape = TwitchHTTPFixture([(200, identityJSON), (200, "{}")], delay: 40_000_000)
        let api = try NTVTwitchAPI(clientID: "ntvtest", transport: { try await tape.send($0) })
        let storage = TwitchMemoryCredentials(try JSONDecoder().decode(NTVTwitchTokens.self, from: Data(tokenJSON.utf8)))
        let session = try NTVTwitchSession(api: api, storage: .init(load: { storage.tokens }, save: { storage.tokens = $0 }, remove: { storage.tokens = nil }))
        let pending = Task { try await session.validateSession() }
        while await tape.requests.isEmpty { await Task.yield() }
        try await session.disconnect()
        do { _ = try await pending.value; XCTFail("A response from the disconnected session must be discarded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(storage.tokens)
        do { _ = try await session.validateSession(); XCTFail("Disconnected session must remain empty") }
        catch { XCTAssertEqual(error as? NTVTwitchError, .unauthorized) }
    }
}

private actor TwitchHTTPFixture {
    private var replies: [(Int, String)]
    private let delay: UInt64
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)], delay: UInt64 = 0) { self.replies = replies; self.delay = delay }
    func replace(_ replies: [(Int, String)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw NTVTwitchError.invalidResponse }
        let reply = replies.removeFirst()
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}
private actor TwitchWaitFixture {
    private(set) var values: [UInt64] = []
    func append(_ value: UInt64) { values.append(value) }
}
private final class TwitchMemoryCredentials {
    var tokens: NTVTwitchTokens?
    init(_ tokens: NTVTwitchTokens?) { self.tokens = tokens }
}

private final class TwitchSecretFixture: NTVSecretStorage {
    var values: [String: Data] = [:]
    var failRemove = false
    var failWrite = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw NTVTwitchError.secureStorage }
        values[key] = data
    }
    func remove(_ key: String) throws {
        if failRemove { throw NTVTwitchError.secureStorage }
        values.removeValue(forKey: key)
    }
}
