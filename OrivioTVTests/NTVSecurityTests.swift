import XCTest
import UIKit
@testable import OrivioTV

final class NTVSecurityTests: XCTestCase {
    func testPublicCinemetaCatalogAliasDoesNotAcceptConfiguredURLs() throws {
        let source = try XCTUnwrap(URL(string: "https://v3-cinemeta.strem.io/catalog/movie/top.json"))
        let destination = try XCTUnwrap(URL(string: "https://cinemeta-catalogs.strem.io/top/catalog/movie/top.json"))
        XCTAssertTrue(NTVAddonTransportPolicy.permitsRedirect(from: source, to: destination))
        for raw in ["https://v3-cinemeta.strem.io/PRIVATE-KEY/catalog/movie/top.json",
                    "https://v3-cinemeta.strem.io/catalog/movie/top.json?token=PRIVATE-KEY",
                    "https://v3-cinemeta.strem.io/catalog/movie/PRIVATE-KEY.json",
                    "https://other.invalid/catalog/movie/top.json",
                    "https://v3-cinemeta.strem.io/meta/movie/tt123.json"] {
            XCTAssertFalse(NTVAddonTransportPolicy.permitsRedirect(from: try XCTUnwrap(URL(string: raw)), to: destination))
        }
        for raw in ["http://cinemeta-catalogs.strem.io/top/catalog/movie/top.json",
                    "https://cinemeta-catalogs.strem.io:8443/top/catalog/movie/top.json",
                    "https://cinemeta-catalogs.strem.io/top/catalog/movie/top.json?token=PRIVATE-KEY",
                    "https://cinemeta-catalogs.strem.io/unrelated/catalog/movie/top.json"] {
            XCTAssertFalse(NTVAddonTransportPolicy.permitsRedirect(from: source, to: try XCTUnwrap(URL(string: raw))))
        }
    }
    func testAddonTargetsRejectCredentialsAndNonHTTPProtocols() {
        let rejected = ["https://user:PRIVATE-URL-SENTINEL@addon.invalid/manifest.json",
                        "https://user@addon.invalid/manifest.json", "file:///tmp/private.json",
                        "javascript:alert(1)", "data:application/json,{}", "https:///manifest.json",
                        "https://addon.invalid:0/manifest.json", "https://addon.invalid:65536/manifest.json",
                        "https://addon.invalid/\nmanifest.json",
                        "https://addon.invalid/" + String(repeating: "x", count: 16_384)]
        for raw in rejected {
            XCTAssertThrowsError(try NTVAddonTransportPolicy.target(raw)) { error in
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE-URL-SENTINEL"))
                XCTAssertFalse(error.localizedDescription.contains("addon.invalid"))
            }
        }
    }

    func testAddonTargetsPreserveConfiguredPathAndQuery() throws {
        for raw in ["https://addon.invalid/PRIVATE-PATH/manifest.json?token=PRIVATE-QUERY",
                    "http://192.168.1.2:8099/config/manifest.json", "http://[::1]:8099/manifest.json"] {
            XCTAssertEqual(try NTVAddonTransportPolicy.target(raw).absoluteString, raw)
        }
    }

    func testAddonRedirectPolicyRejectsOtherOriginsAndDowngrades() throws {
        let source = try XCTUnwrap(URL(string: "https://addon.invalid/PRIVATE-PATH/manifest.json"))
        for raw in ["https://other.invalid/PRIVATE-PATH/manifest.json", "http://addon.invalid/manifest.json",
                    "https://addon.invalid:8443/manifest.json", "https://user@addon.invalid/manifest.json",
                    "file:///tmp/manifest.json"] {
            XCTAssertFalse(NTVAddonTransportPolicy.permitsRedirect(from: source, to: try XCTUnwrap(URL(string: raw))))
        }
        XCTAssertTrue(NTVAddonTransportPolicy.permitsRedirect(from: source,
            to: try XCTUnwrap(URL(string: "https://ADDON.invalid:443/next.json"))))
        XCTAssertTrue(NTVAddonTransportPolicy.permitsRedirect(
            from: try XCTUnwrap(URL(string: "http://addon.invalid/manifest.json")), to: source))
        XCTAssertFalse(NTVAddonTransportPolicy.permitsRedirect(
            from: try XCTUnwrap(URL(string: "http://addon.invalid/manifest.json")),
            to: try XCTUnwrap(URL(string: "http://addon.invalid/next.json")), current: source),
            "An HTTP entry point cannot permit a later HTTPS-to-HTTP downgrade.")
    }

    func testAddonSessionDoesNotShareCookiesCredentialsOrDiskCache() {
        let session = NTVAddonTransportPolicy.makeSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testAddonCollectorDoesNotForwardConfiguredURLToAnotherService() async throws {
        let destination = try NTVAddonHTTPFixture()
        defer { destination.stop() }
        let target = try await destination.start()
        let redirect = try NTVAddonHTTPFixture(redirectTo: target.appendingPathComponent("PRIVATE-REDIRECT-SENTINEL"))
        defer { redirect.stop() }
        let source = try await redirect.start()
        let session = NTVAddonTransportPolicy.makeSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await NTVBoundedResponse.data(
            for: URLRequest(url: source), session: session, maximumBytes: 1024)
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(destination.requests.count, 0, "A different service port must not receive the configured path.")
    }

    func testAddonCollectorFollowsSameOriginWithoutSharingCookies() async throws {
        let server = try NTVAddonHTTPFixture(redirectWithinOrigin: true)
        defer { server.stop() }
        let source = try await server.start()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/",
            .name: "ntv-security-fixture", .value: "PRIVATE-COOKIE-SENTINEL"]))
        HTTPCookieStorage.shared.setCookies([cookie], for: source, mainDocumentURL: source)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        XCTAssertTrue(HTTPCookieStorage.shared.cookies(for: source)?.contains {
            $0.name == cookie.name && $0.value == "PRIVATE-COOKIE-SENTINEL"
        } == true, "The shared-cookie sentinel must exist before checking isolation.")
        let session = NTVAddonTransportPolicy.makeSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (body, response) = try await NTVBoundedResponse.data(
            for: URLRequest(url: source), session: session, maximumBytes: 1024)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(body, Data("{}".utf8))
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertFalse(server.requests.contains { $0.contains("PRIVATE-COOKIE-SENTINEL") })
    }

    func testBoundedReceptionPreservesAuthenticatedRedirectProtection() async throws {
        let destination = try NTVGzipHTTPFixture(payload: Data())
        defer { destination.stop() }
        let target = try await destination.start()
        let redirect = try NTVGzipHTTPFixture(payload: Data("redirect".utf8), redirectTo: target)
        defer { redirect.stop() }
        let url = try await redirect.start()
        let session = NTVAuthenticatedSession.make()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Bearer PRIVATE-REDIRECT-SENTINEL", forHTTPHeaderField: "Authorization")
        let (_, response) = try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 1024)
        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(destination.requestsReceived, 0, "The chunk collector must not override the existing redirect guard")
    }

    func testGzipBodyIsBoundedAfterActualHTTPDecompression() async throws {
        // 306 wire bytes expand into a 256KiB JSON value.
        let gzip = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAACCu3BMQkAIAAEwC4fwzaCIC7iKIjd3c1wdyertjZmT8kGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjkPt8jZscOAAQA"))
        XCTAssertLessThan(gzip.count, 1024)
        let server = try NTVGzipHTTPFixture(payload: gzip)
        defer { server.stop() }
        let url = try await server.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await NTVBoundedResponse.data(for: URLRequest(url: url), session: session, maximumBytes: 1024)
            XCTFail("The decoded bytes, not just compressed Content-Length, must be bounded")
        } catch NTVBoundedResponse.Failure.tooLarge {}
    }

    func testOversizedDeclaredResponseCancelsBeforeReadingItsBody() async throws {
        let stopped = expectation(description: "Oversized transfer cancelled")
        let probe = NTVBoundedHTTPProbe(declaredLength: 4096, stall: true, onStop: { stopped.fulfill() })
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        do { _ = try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 512); XCTFail("Must reject the body") }
        catch NTVBoundedResponse.Failure.tooLarge {}
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertEqual(probe.bytesSent, 0)
    }

    func testResponseWithoutContentLengthIsStoppedDuringReception() async throws {
        let stopped = expectation(description: "Streaming transfer cancelled")
        let body = Data(repeating: 120, count: 64 << 10)
        let probe = NTVBoundedHTTPProbe(body: body, onStop: { stopped.fulfill() })
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        do { _ = try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 1024); XCTFail("Must reject unknown-sized body") }
        catch NTVBoundedResponse.Failure.tooLarge {}
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertLessThan(probe.bytesSent, body.count, "Cancel before downloading the full oversized response")
    }

    func testResponseAtTheLimitPreservesEveryByte() async throws {
        let body = Data(repeating: 120, count: 4096)
        let probe = NTVBoundedHTTPProbe(body: body, declaredLength: body.count)
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        let result = try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: body.count)
        XCTAssertEqual(result.0, body)
        XCTAssertEqual(result.1.statusCode, 200)
    }

    func testCancellingAStalledResponseCancelsItsNetworkTask() async throws {
        let headers = expectation(description: "Headers received")
        let stopped = expectation(description: "Network transfer cancelled")
        let probe = NTVBoundedHTTPProbe(stall: true, onHeaders: { headers.fulfill() }, onStop: { stopped.fulfill() })
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        let pending = Task { try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 512) }
        await fulfillment(of: [headers], timeout: 3)
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancellation must not return a body") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [stopped], timeout: 3)
    }

    func testCacheBudgetUsesBytesInsteadOfOnlyEntryCount() {
        let cache = StremioResponseCache(entryLimit: 20, byteLimit: 8)
        cache.store(Data(repeating: 1, count: 6), for: "first")
        cache.store(Data(repeating: 2, count: 6), for: "second")
        XCTAssertNil(cache.data(for: "first", ttl: 60))
        XCTAssertEqual(cache.data(for: "second", ttl: 60), Data(repeating: 2, count: 6))
    }

    func testReplacingCachedBodyReclaimsThePreviousBytes() {
        let cache = StremioResponseCache(entryLimit: 20, byteLimit: 8)
        cache.store(Data(repeating: 1, count: 6), for: "same")
        cache.store(Data(repeating: 2, count: 2), for: "same")
        cache.store(Data(repeating: 3, count: 6), for: "other")
        XCTAssertEqual(cache.data(for: "same", ttl: 60), Data(repeating: 2, count: 2))
        XCTAssertNotNil(cache.data(for: "other", ttl: 60))
    }

    func testOverBudgetEntryIsNotRetainedAndRemovalReclaimsBytes() {
        let cache = StremioResponseCache(entryLimit: 20, byteLimit: 8)
        cache.store(Data(repeating: 1, count: 9), for: "oversized")
        XCTAssertNil(cache.data(for: "oversized", ttl: 60))
        cache.store(Data(repeating: 1, count: 6), for: "removed")
        cache.remove("removed")
        cache.store(Data(repeating: 2, count: 8), for: "remaining")
        XCTAssertNotNil(cache.data(for: "remaining", ttl: 60))
    }

    func testMemoryWarningClearsBodiesAndTheirByteBudget() {
        let cache = StremioResponseCache(entryLimit: 20, byteLimit: 8)
        cache.store(Data(repeating: 1, count: 6), for: "before")
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(cache.data(for: "before", ttl: 60))
        cache.store(Data(repeating: 2, count: 8), for: "after")
        XCTAssertNotNil(cache.data(for: "after", ttl: 60))
    }

    @MainActor
    func testUnconfiguredAccountDoesNotStartLoginOrShowAnError() async {
        let session = stubSession()
        defer { session.invalidateAndCancel(); AccountRequestGate.reset() }
        let request = expectation(description: "An unconfigured account cannot send a request")
        request.isInverted = true
        AccountRequestGate.started = { request.fulfill() }
        let manager = OrivioAccountManager(urlSession: session, baseURL: "", fallbackURL: "", restore: false)
        manager.startQRLogin()
        await fulfillment(of: [request], timeout: 0.1)
        XCTAssertNil(manager.qrLogin)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.authState, .signedOut)
    }

    func testAddonDiagnosticsNeverEchoPrivateURLsOrErrorContents() {
        let sentinel = "PRIVATE-ADDON-SENTINEL"
        for raw in ["https://user:\(sentinel)@private.invalid/\(sentinel)/manifest.json?key=\(sentinel)",
                    "https://127.0.0.1/\(sentinel)/catalog/movie/\(sentinel).json",
                    "https://private.invalid/unknown/\(sentinel)", "invalid \(sentinel)"] {
            let label = AppProbe.requestName(raw)
            XCTAssertFalse(label.contains(sentinel))
            XCTAssertFalse(label.contains("private.invalid"))
            XCTAssertFalse(label.contains("127.0.0.1"))
        }
        let network = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://private.invalid/\(sentinel)")!])
        let errors: [Error] = [StremioAPIError.badURL(sentinel), network,
                              NSError(domain: sentinel, code: 42, userInfo: [NSLocalizedDescriptionKey: sentinel])]
        for error in errors {
            XCTAssertFalse(NTVAddonDiagnostics.failure(error).contains(sentinel))
        }
    }

    func testLinkedMediaLibrariesInventoryAndPatchedVLC() {
        let vlc = NTVMediaDependencyAudit.vlcVersion
        let ffmpeg = NTVMediaDependencyAudit.ffmpegVersion
        print("[NTV audit] linked libVLC=\(vlc); FFmpeg=\(ffmpeg)")
        XCTAssertTrue(vlc.hasPrefix("3.0.24 "), "The linked VLC must include the audited security update.")
        XCTAssertEqual(ffmpeg, "6.1.6", "The actual linked FFmpeg must be the rebuilt maintenance release.")
    }

    func testLegacyCredentialMigratesWithoutKeepingPlaintext() throws {
        let defaults = UserDefaults(suiteName: "ntv.audit." + UUID().uuidString)!
        let secrets = MemorySecretStorage()
        let prefs = NTVSecurePreferences(defaults: defaults, secrets: secrets)
        let key = "orivio.stremio.authKey.v1"
        defaults.set("offline-fixture", forKey: key)
        XCTAssertEqual(prefs.string(forKey: key), "offline-fixture")
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertNotNil(secrets.values[key])
        XCTAssertEqual(NTVSecurePreferences(defaults: defaults, secrets: secrets).string(forKey: key), "offline-fixture")
    }

    func testFailedMigrationDoesNotExposeOrDestroyLegacyCredential() {
        let defaults = UserDefaults(suiteName: "ntv.audit." + UUID().uuidString)!
        let secrets = MemorySecretStorage(); secrets.failWrite = true
        let prefs = NTVSecurePreferences(defaults: defaults, secrets: secrets)
        let key = "orivio.session.v1"
        defaults.set(Data("offline-fixture".utf8), forKey: key)
        XCTAssertNil(prefs.data(forKey: key), "A storage failure must not fall back to plaintext.")
        XCTAssertNotNil(defaults.data(forKey: key), "Only a confirmed secure migration may remove the original.")
        secrets.failWrite = false
        XCTAssertEqual(prefs.data(forKey: key), Data("offline-fixture".utf8))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testCredentialsKeepProfileScopeAndRevocationSurvivesFailedDeletion() {
        let defaults = UserDefaults(suiteName: "ntv.audit." + UUID().uuidString)!
        let secrets = MemorySecretStorage()
        let prefs = NTVSecurePreferences(defaults: defaults, secrets: secrets)
        let a = "orivio.trakt.tokens.v1.p1", b = "orivio.trakt.tokens.v1.p2"
        XCTAssertTrue(prefs.set(Data("a".utf8), forKey: a))
        XCTAssertTrue(prefs.set(Data("b".utf8), forKey: b))
        secrets.failDelete = true
        XCTAssertFalse(prefs.removeObject(forKey: a))
        let restored = NTVSecurePreferences(defaults: defaults, secrets: secrets)
        XCTAssertNil(restored.data(forKey: a), "Signing out must survive a failed Keychain deletion.")
        XCTAssertEqual(restored.data(forKey: b), Data("b".utf8))
        XCTAssertNil(defaults.data(forKey: b))
        XCTAssertTrue(restored.set(Data("new-a".utf8), forKey: a))
        XCTAssertEqual(restored.data(forKey: a), Data("new-a".utf8))
    }

    func testActualKeychainRoundTrip() throws {
        let storage = NTVKeychainStorage(service: "ntv.audit." + UUID().uuidString)
        defer { try? storage.remove("fixture") }
        try storage.write(Data("offline-fixture".utf8), key: "fixture")
        XCTAssertEqual(try storage.read("fixture"), Data("offline-fixture".utf8))
        try storage.remove("fixture")
        XCTAssertNil(try storage.read("fixture"))
    }

    func testPhoneImportRequiresCapabilityHostAndOrigin() throws {
        var policy = NTVAddonImportPolicy(host: "192.0.2.1:8099")
        XCTAssertEqual(policy.authorize(try request(path: "/", host: policy.host)), 403)
        XCTAssertEqual(policy.authorize(try request(path: policy.path, host: "evil.invalid:8099")), 403)
        XCTAssertEqual(policy.authorize(try request(path: policy.path, host: policy.host, origin: "https://evil.invalid", method: "POST")), 403)
        XCTAssertEqual(policy.authorize(try request(path: policy.path, host: policy.host, origin: policy.origin, method: "POST")), 200)
        XCTAssertNotEqual(policy.path, NTVAddonImportPolicy(host: policy.host).path)
    }

    func testPhoneImportExpiryAndFloodLimit() throws {
        let now = Date()
        var policy = NTVAddonImportPolicy(host: "192.0.2.1:8099", now: now)
        let post = try request(path: policy.path, host: policy.host, origin: policy.origin, method: "POST")
        for _ in 0..<12 { XCTAssertEqual(policy.authorize(post, now: now), 200) }
        XCTAssertEqual(policy.authorize(post, now: now), 429)
        XCTAssertEqual(policy.authorize(post, now: now.addingTimeInterval(61)), 200)
        XCTAssertEqual(policy.authorize(post, now: policy.expiresAt), 410)
    }

    func testHTTPFramingRejectsAmbiguityAndOversizedBodies() throws {
        for headers in ["Content-Length: 0\r\nContent-Length: 1", "Transfer-Encoding: chunked\r\nContent-Length: 0", "Content-Length: 32769", "Content-Length: -1", ""] {
            XCTAssertNil(NTVImportHTTPRequest(Data("POST / HTTP/1.1\r\nHost: test\r\n\(headers)\r\n\r\n".utf8)))
        }
        let incomplete = try XCTUnwrap(NTVImportHTTPRequest(Data("POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 5\r\n\r\nabc".utf8)))
        XCTAssertFalse(incomplete.isComplete)
        XCTAssertTrue(try XCTUnwrap(NTVImportHTTPRequest(Data("POST / HTTP/1.1\r\nHost: test\r\nContent-Length: 5\r\n\r\nabcde".utf8))).isComplete)
    }

    func testAuthenticatedRequestsRequireHTTPSWithoutURLCredentials() throws {
        XCTAssertTrue(NTVAuthenticatedSession.permits(try XCTUnwrap(URL(string: "https://account.example.invalid/auth"))))
        for raw in ["http://account.example.invalid/auth", "https://user:password@account.example.invalid/auth", "file:///tmp/auth"] {
            XCTAssertFalse(NTVAuthenticatedSession.permits(try XCTUnwrap(URL(string: raw))))
        }
        let session = NTVAuthenticatedSession.make()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
    }

    @MainActor
    func testRealPhoneServerRejectsUnpairedPostsAndDoesNotEchoPrivateLink() async throws {
        let server = AddonImportServer()
        defer { server.stop() }
        var installed = 0
        server.onInstall = { url in
            installed += 1
            return .success(.init(manifestURL: url, name: "Fixture", logo: nil, description: nil))
        }
        server.start()
        for _ in 0..<50 {
            if server.address != nil || server.lastError != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let address = try XCTUnwrap(server.address, server.lastError ?? "Server did not start")
        let url = try XCTUnwrap(URL(string: address))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (page, response) = try await session.data(from: url)
        let headers = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(headers.statusCode, 200)
        XCTAssertEqual(headers.value(forHTTPHeaderField: "Referrer-Policy"), "no-referrer")
        XCTAssertEqual(headers.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertTrue(headers.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("form method=post"))
        var post = URLRequest(url: url)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data("url=https%3A%2F%2Faddon.example.invalid%2Fprivate-fixture%2Fmanifest.json".utf8)
        post.setValue("https://untrusted.example.invalid", forHTTPHeaderField: "Origin")
        let (_, rejected) = try await session.data(for: post)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(installed, 0)
        post.setValue("http://\(url.host!):\(url.port!)", forHTTPHeaderField: "Origin")
        let (added, accepted) = try await session.data(for: post)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(installed, 1)
        XCTAssertFalse(String(decoding: added, as: UTF8.self).contains("private-fixture"))
        var unpaired = post
        unpaired.url = url.deletingLastPathComponent()
        let (_, denied) = try await session.data(for: unpaired)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(installed, 1)
    }

    @MainActor
    func testLateManifestCannotRestoreRetiredAccountsPrivateAddon() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("orivio.addons.") }
        defer {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("orivio.addons.") { defaults.removeObject(forKey: key) }
            for (key, value) in saved { defaults.set(value, forKey: key) }
        }
        let gate = AddonManifestGate()
        let manager = AddonManager(startRefresh: false) { _ in await gate.manifest() }
        manager.clearAll()
        let pending = Task { try await manager.install(manifestURL: "https://addon.example.invalid/old-account/manifest.json") }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let requestStarted = await gate.started
        XCTAssertTrue(requestStarted)
        manager.clearAll()
        try await gate.release()
        do { try await pending.value; XCTFail("A retired account's manifest must be rejected.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(manager.addons.isEmpty)
    }

    @MainActor
    func testStremioRetiredLoginCannotRestoreCredentialsOrReplaceNewerLogin() {
        let defaults = UserDefaults(suiteName: "ntv.audit." + UUID().uuidString)!
        let prefs = NTVSecurePreferences(defaults: defaults, secrets: MemorySecretStorage())
        let store = StremioAccountStore(preferences: prefs, logout: { _ in })
        let first = store.beginAuthentication()
        store.signOut()
        XCTAssertFalse(store.signIn(authKey: "fixture-a", user: nil, expectedGeneration: first))
        XCTAssertNil(store.authKey)
        XCTAssertNil(prefs.string(forKey: "orivio.stremio.authKey.v1"))
        let older = store.beginAuthentication()
        let newer = store.beginAuthentication()
        XCTAssertTrue(store.signIn(authKey: "fixture-b", user: StremioUser(email: "b@example.invalid", avatar: nil), expectedGeneration: newer))
        XCTAssertFalse(store.signIn(authKey: "fixture-a", user: nil, expectedGeneration: older))
        XCTAssertEqual(store.authKey, "fixture-b")
        XCTAssertEqual(store.email, "b@example.invalid")
        XCTAssertEqual(prefs.string(forKey: "orivio.stremio.authKey.v1"), "fixture-b")
        XCTAssertNil(defaults.string(forKey: "orivio.stremio.authKey.v1"))
    }

    @MainActor
    func testLateStremioPullCannotMergeAfterSignOut() async throws {
        let gate = StremioLibraryGate()
        let defaults = UserDefaults(suiteName: "ntv.audit." + UUID().uuidString)!
        let store = StremioAccountStore(preferences: NTVSecurePreferences(defaults: defaults, secrets: MemorySecretStorage()), logout: { _ in })
        store.signIn(authKey: "fixture-a", user: nil)
        let generation = store.sessionGeneration
        let manager = AddonManager(startRefresh: false) { _ in throw CancellationError() }
        let before = manager.addons.map(\.manifestURL)
        let library = LibraryStore(), progress = ProgressStore(), watched = WatchedStore()
        let rows = try JSONDecoder().decode([StremioLibraryItem].self, from: Data(#"[{"_id":"ntv.old.account.fixture","type":"movie","name":"Offline fixture"}]"#.utf8))
        let beforeLibrary = library.allForSync().map(\.id)
        let pending = Task {
            await StremioSync.pull(authKey: "fixture-a", addonManager: manager, library: library, progress: progress, watched: watched,
                isCurrent: { store.sessionGeneration == generation && store.authKey == "fixture-a" },
                libraryLoader: { _ in await gate.wait() },
                addonLoader: { _ in [StremioAddonDescriptor(transportUrl: "https://addon.example.invalid/old-account/manifest.json")] })
        }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let requestStarted = await gate.started
        XCTAssertTrue(requestStarted)
        store.signOut()
        await gate.release(rows)
        let result = await pending.value
        XCTAssertEqual(result, "Synchronisation annulée")
        XCTAssertEqual(manager.addons.map(\.manifestURL), before)
        XCTAssertEqual(library.allForSync().map(\.id), beforeLibrary)
    }

    @MainActor
    func testCurrentStremioPullCanStillImportAddonOffline() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("orivio.addons.") }
        defer {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("orivio.addons.") { defaults.removeObject(forKey: key) }
            for (key, value) in saved { defaults.set(value, forKey: key) }
        }
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"ntv.fixture","name":"Fixture","version":"1","types":["movie"],"resources":[],"catalogs":[]}"#.utf8))
        let manager = AddonManager(startRefresh: false) { _ in manifest }
        manager.clearAll()
        let result = await StremioSync.pull(authKey: "fixture-a", addonManager: manager,
            library: LibraryStore(), progress: ProgressStore(), watched: WatchedStore(), isCurrent: { true },
            libraryLoader: { _ in [] },
            addonLoader: { _ in [StremioAddonDescriptor(transportUrl: "https://addon.example.invalid/current-account/manifest.json")] })
        XCTAssertTrue(result.hasPrefix("Pulled 1 add-ons"))
        XCTAssertEqual(manager.addons.count, 1)
        XCTAssertEqual(manager.addons.first?.manifest.id, "ntv.fixture")
    }

    @MainActor
    func testLateEmailLoginCannotUndoSignOut() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); AccountRequestGate.reset() }
        let started = expectation(description: "login started")
        AccountRequestGate.started = { started.fulfill() }
        let manager = OrivioAccountManager(urlSession: session, baseURL: "https://account.example.invalid", fallbackURL: "", restore: false)
        let login = Task { await manager.signIn(email: "a@example.invalid", password: "offline-fixture") }
        await fulfillment(of: [started], timeout: 3)
        manager.signOut()
        try AccountRequestGate.complete(email: "a@example.invalid", user: "person-a")
        await login.value
        XCTAssertEqual(manager.authState, .signedOut)
        XCTAssertNil(manager.accessToken)
    }

    @MainActor
    func testNewerLoginWinsOverOlderResponse() async throws {
        let saved = OrivioSession.load()
        defer { OrivioSession.clear(); saved?.save() }
        let session = stubSession()
        defer { session.invalidateAndCancel(); AccountRequestGate.reset() }
        let first = expectation(description: "first login")
        AccountRequestGate.started = { first.fulfill() }
        let manager = OrivioAccountManager(urlSession: session, baseURL: "https://account.example.invalid", fallbackURL: "", restore: false)
        let old = Task { await manager.signIn(email: "a@example.invalid", password: "offline-fixture") }
        await fulfillment(of: [first], timeout: 3)
        let second = expectation(description: "second login")
        AccountRequestGate.started = { second.fulfill() }
        let newer = Task { await manager.signIn(email: "b@example.invalid", password: "offline-fixture") }
        await fulfillment(of: [second], timeout: 3)
        try AccountRequestGate.complete(email: "b@example.invalid", user: "person-b")
        await newer.value
        try AccountRequestGate.complete(email: "a@example.invalid", user: "person-a")
        await old.value
        XCTAssertEqual(manager.currentUserID, "person-b")
    }

    private func request(path: String, host: String, origin: String? = nil, method: String = "GET") throws -> NTVImportHTTPRequest {
        let fields = origin.map { "Origin: \($0)\r\n" } ?? ""
        return try XCTUnwrap(NTVImportHTTPRequest(Data("\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\n\(fields)Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 0\r\n\r\n".utf8)))
    }
    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountRequestGate.self]
        return URLSession(configuration: configuration)
    }
}

private final class MemorySecretStorage: NTVSecretStorage {
    var values: [String: Data] = [:]
    var failWrite = false, failDelete = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw NTVKeychainStorage.StorageError.unavailable }
        values[key] = data
    }
    func remove(_ key: String) throws {
        if failDelete { throw NTVKeychainStorage.StorageError.unavailable }
        values[key] = nil
    }
}

private actor StremioLibraryGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<[StremioLibraryItem], Never>?
    func wait() async -> [StremioLibraryItem] {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ rows: [StremioLibraryItem]) {
        continuation?.resume(returning: rows)
        continuation = nil
    }
}

private actor AddonManifestGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<AddonManifest, Never>?
    func manifest() async -> AddonManifest {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() throws {
        let value = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"ntv.fixture","name":"Fixture","version":"1","types":["movie"],"resources":[],"catalogs":[]}"#.utf8))
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private final class AccountRequestGate: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [String: AccountRequestGate] = [:]
    nonisolated(unsafe) static var started: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "account.example.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024), body = Data()
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
            data = body
        }
        let body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
        Self.lock.lock(); Self.pending[body?["email"] as? String ?? ""] = self; let callback = Self.started; Self.lock.unlock()
        callback?()
    }
    override func stopLoading() {}
    static func complete(email: String, user: String) throws {
        lock.lock(); let pendingRequest = pending.removeValue(forKey: email); lock.unlock()
        let instance = try XCTUnwrap(pendingRequest)
        let claims = try JSONSerialization.data(withJSONObject: ["sub": user, "exp": Date().addingTimeInterval(3600).timeIntervalSince1970]).base64EncodedString()
        let payload = try JSONSerialization.data(withJSONObject: ["access_token": "fixture.\(claims).fixture", "refresh_token": "offline-fixture"])
        instance.client?.urlProtocol(instance, didReceive: HTTPURLResponse(url: instance.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        instance.client?.urlProtocol(instance, didLoad: payload)
        instance.client?.urlProtocolDidFinishLoading(instance)
    }
    static func reset() { lock.lock(); pending = [:]; started = nil; lock.unlock() }
}
