import XCTest
@testable import OrivioTV

final class NTVTwitchTests: XCTestCase {
    private let tokenJSON = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":14400,"scope":["user:read:follows"],"token_type":"bearer"}"#
    private let identityJSON = #"{"client_id":"ntvtest","user_id":"42","login":"fixture","scopes":["user:read:follows"],"expires_in":14400}"#
    private let deviceJSON = #"{"device_code":"fixture-device","user_code":"ABCD","expires_in":1800,"interval":5,"verification_uri":"https://www.twitch.tv/activate?public=true&device-code=ABCD"}"#

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
