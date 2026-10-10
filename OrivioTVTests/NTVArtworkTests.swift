import XCTest
import UIKit
import CryptoKit
@testable import OrivioTV

final class NTVArtworkTests: XCTestCase {
    private enum FixtureFailure: Error { case timeout }
    private func until(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw FixtureFailure.timeout }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ntv-art-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func legacyFile(in directory: URL, key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
    private func sparseFile(_ url: URL, count: Int) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(count))
    }
    @MainActor
    private func png() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 16), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        }
        return try XCTUnwrap(image.pngData())
    }
    private func expectCancellation<T: Sendable>(_ task: Task<T, Error>) async {
        do { _ = try await task.value; XCTFail("Cancelled load returned a value") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation result") }
    }

    func testDeclaredOversizedArtworkIsRejectedBeforeReadingAndNeverCached() async throws {
        let probe = NTVBoundedHTTPProbe(declaredLength: NTVArtworkTransfer.maximumBytes + 1, stall: true)
        let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
        let key = request.url!.absoluteString, cache = ImageCache(directory: dir, session: session)
        do { _ = try await cache.loadImage(for: key, budget: 340, memoryKey: ImageCache.artworkKey(key, budget: 340)); XCTFail("Accepted oversized image") }
        catch NTVBoundedResponse.Failure.tooLarge {}
        XCTAssertEqual(probe.bytesSent, 0)
        let cached = await cache.diskData(for: key)
        XCTAssertNil(cached)
    }

    func testUnknownLengthArtworkStopsAtTheRealReceptionBudget() async throws {
        let probe = NTVBoundedHTTPProbe(body: Data(repeating: 0xA5, count: 20 << 20), chunkSize: 128 << 10, chunkDelay: 0.005)
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        do { _ = try await NTVArtworkTransfer.data(from: request.url!, session: session); XCTFail("Unbounded body accepted") }
        catch NTVBoundedResponse.Failure.tooLarge {}
        try await until { probe.isStopped }
        XCTAssertLessThan(probe.bytesSent, probe.body.count, "The rest of the body must not be downloaded.")
    }

    func testNormalArtworkTransferKeepsAllOriginalBytes() async throws {
        let body = try await png(), probe = NTVBoundedHTTPProbe(body: body, declaredLength: body.count)
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        let received = try await NTVArtworkTransfer.data(from: request.url!, session: session)
        XCTAssertEqual(received, body)
        XCTAssertEqual(probe.requestsReceived, 1)
    }

    func testHTTPFailureCannotBecomeCachedArtwork() async throws {
        let probe = NTVBoundedHTTPProbe(body: Data("unavailable".utf8), statusCode: 503)
        let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
        let key = request.url!.absoluteString, cache = ImageCache(directory: dir, session: session)
        do { _ = try await cache.loadImage(for: key, budget: 340, memoryKey: ImageCache.artworkKey(key, budget: 340)); XCTFail("HTTP error accepted") }
        catch let error as URLError { XCTAssertEqual(error.code, .badServerResponse) }
        let cached = await cache.diskData(for: key)
        XCTAssertNil(cached)
    }

    func testArtworkTransportRejectsNonHTTPAndAuthorityCredentials() async {
        let session = URLSession(configuration: NTVArtworkTransfer.configuration())
        defer { session.invalidateAndCancel() }
        for raw in ["file:///private/image.png", "ftp://image.invalid/a.png", "https://user:sentinel@image.invalid/a.png"] {
            do { _ = try await NTVArtworkTransfer.data(from: URL(string: raw)!, session: session); XCTFail("Unsafe URL accepted") }
            catch let error as URLError { XCTAssertEqual(error.code, .unsupportedURL) }
            catch { XCTFail("Expected URL rejection before any request") }
        }
    }

    func testArtworkSessionHasNoSharedCookiesCredentialsOrHTTPDiskCache() {
        let session = URLSession(configuration: NTVArtworkTransfer.configuration())
        defer { session.invalidateAndCancel() }
        let config = session.configuration
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertNil(config.urlCache)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(config.timeoutIntervalForRequest, 25)
        XCTAssertEqual(config.timeoutIntervalForResource, 45)
    }

    func testBoundedCacheReaderAcceptsAnExactBudgetWithoutChangingBytes() throws {
        let dir = try directory(), file = dir.appendingPathComponent("image")
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = Data(repeating: 0xA5, count: NTVArtworkTransfer.maximumBytes)
        try body.write(to: file)
        XCTAssertEqual(try NTVArtworkTransfer.fileData(from: file), body)
    }

    func testBoundedCacheReaderRejectsOversizedLegacyFile() throws {
        let dir = try directory(), file = dir.appendingPathComponent("legacy")
        defer { try? FileManager.default.removeItem(at: dir) }
        try sparseFile(file, count: NTVArtworkTransfer.maximumBytes + 1)
        XCTAssertThrowsError(try NTVArtworkTransfer.fileData(from: file)) {
            guard case NTVBoundedResponse.Failure.tooLarge = $0 else { return XCTFail("Expected file-size rejection") }
        }
    }

    func testCancelledCacheReaderStopsBeforeOpeningAnyFile() async throws {
        let dir = try directory(), missing = dir.appendingPathComponent("does-not-exist")
        defer { try? FileManager.default.removeItem(at: dir) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try NTVArtworkTransfer.fileData(from: missing)
        }
        await expectCancellation(task)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testActualImageLoadReusesMemoryThenDiskWithoutAnotherRequest() async throws {
        let body = try await png(), probe = NTVBoundedHTTPProbe(body: body)
        let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
        let key = request.url!.absoluteString, rendition = ImageCache.artworkKey(key, budget: 340)
        let cache = ImageCache(directory: dir, session: session)
        let first = try await cache.loadImage(for: key, budget: 340, memoryKey: rendition)
        let same = try await cache.loadImage(for: key, budget: 340, memoryKey: rendition)
        XCTAssertTrue(first === same)
        cache.dropDecoded()
        let reread = try await cache.loadImage(for: key, budget: 340, memoryKey: rendition)
        XCTAssertEqual(reread?.cgImage?.width, 32)
        XCTAssertEqual(reread?.cgImage?.height, 16)
        XCTAssertEqual(probe.requestsReceived, 1, "A cold decoded cache must still use the persisted bytes.")
        let disk = await cache.diskData(for: key)
        XCTAssertEqual(disk, body)
    }

    func testActualConcurrentImageLoadsShareTransferAndDecodedObject() async throws {
        let body = try await png(), probe = NTVBoundedHTTPProbe(body: body, chunkSize: 16, chunkDelay: 0.01)
        let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
        let key = request.url!.absoluteString, rendition = ImageCache.artworkKey(key, budget: 340)
        let cache = ImageCache(directory: dir, session: session)
        async let a = cache.loadImage(for: key, budget: 340, memoryKey: rendition)
        async let b = cache.loadImage(for: key, budget: 340, memoryKey: rendition)
        let (first, second) = try await (a, b)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertEqual(probe.requestsReceived, 1)
    }

    func testCancellingTheActualImageLoadStopsItsHTTPTaskAndDoesNotPersist() async throws {
        let headers = expectation(description: "Artwork headers"), stopped = expectation(description: "Artwork request stopped")
        let probe = NTVBoundedHTTPProbe(stall: true, onHeaders: { headers.fulfill() }, onStop: { stopped.fulfill() })
        let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
        let key = request.url!.absoluteString, cache = ImageCache(directory: dir, session: session)
        let task = Task {
            let image = try await cache.loadImage(for: key, budget: 340, memoryKey: ImageCache.artworkKey(key, budget: 340))
            return image != nil
        }
        await fulfillment(of: [headers], timeout: 5)
        task.cancel()
        await expectCancellation(task)
        await fulfillment(of: [stopped], timeout: 5)
        let disk = await cache.diskData(for: key)
        XCTAssertNil(disk)
    }

    func testCorruptOrOversizedOldCacheGetsAValidNetworkReplacement() async throws {
        for oversized in [false, true] {
            let body = try await png(), probe = NTVBoundedHTTPProbe(body: body)
            let (session, request) = NTVBoundedHTTPFixture.register(probe), dir = try directory()
            defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id); try? FileManager.default.removeItem(at: dir) }
            let key = request.url!.absoluteString, cache = ImageCache(directory: dir, session: session)
            let oldFile = legacyFile(in: dir, key: key), corrupt = Data("old-invalid-image".utf8)
            if oversized { try sparseFile(oldFile, count: 17 << 20) } else { try corrupt.write(to: oldFile) }
            let oldBytes = await cache.diskData(for: key)
            XCTAssertEqual(oldBytes, oversized ? nil : corrupt, "The test must actually reach the old cache file.")
            let image = try await cache.loadImage(for: key, budget: 340, memoryKey: ImageCache.artworkKey(key, budget: 340))
            XCTAssertEqual(image?.cgImage?.width, 32)
            XCTAssertEqual(probe.requestsReceived, 1)
            let replaced = await cache.diskData(for: key)
            XCTAssertEqual(replaced, body)
        }
    }

    func testArtworkKeysSeparateURLFragmentsSizesAndBlurRecipes() {
        let base = "https://image.invalid/poster"
        XCTAssertNotEqual(ImageCache.artworkKey(base + "#340", budget: nil), ImageCache.artworkKey(base, budget: 340))
        XCTAssertNotEqual(ImageCache.artworkKey(base + "#blur60", budget: nil), ImageCache.artworkKey(base, budget: 480, kind: "blur:60"))
        XCTAssertNotEqual(ImageCache.artworkKey(base, budget: 480), ImageCache.artworkKey(base, budget: 480, kind: "blur:60"))
        XCTAssertFalse(ImageCache.artworkKey(base + "?token=sentinel", budget: 340).contains("sentinel"))
    }

    func testFullImageLoadWindowBoundsActualTransfersAcrossSeveralURLs() async throws {
        let probes = (0..<4).map { _ in NTVBoundedHTTPProbe(stall: true) }
        let bindings = probes.map { NTVBoundedHTTPFixture.register($0) }, dir = try directory()
        // Register all probes, then use one session for their four URL routes.
        let session = bindings[0].0, cache = ImageCache(directory: dir, session: session, loadLimit: 2)
        defer {
            for binding in bindings { binding.0.invalidateAndCancel() }
            for probe in probes { NTVBoundedHTTPFixture.remove(probe.id) }
            try? FileManager.default.removeItem(at: dir)
        }
        let tasks = bindings.map { binding in
            let key = binding.1.url!.absoluteString
            return Task {
                let image = try await cache.loadImage(for: key, budget: 340, memoryKey: ImageCache.artworkKey(key, budget: 340))
                return image != nil
            }
        }
        try await until { await cache.loadActivity.waiters == 4 }
        try await until { probes.reduce(0) { $0 + $1.requestsReceived } == 2 }
        let activity = await cache.loadActivity
        XCTAssertEqual(activity.running, 2)
        XCTAssertEqual(activity.queued, 2)
        // Cancel queued work first; it must not start as the active slots free.
        let queued = probes.indices.filter { probes[$0].requestsReceived == 0 }
        for index in queued { tasks[index].cancel() }
        try await until { await cache.loadActivity.queued == 0 }
        for index in probes.indices { tasks[index].cancel() }
        for task in tasks {
            await expectCancellation(task)
        }
        try await until { probes.filter { $0.requestsReceived > 0 }.allSatisfy { $0.isStopped } }
        XCTAssertEqual(probes.reduce(0) { $0 + $1.requestsReceived }, 2)
    }
}
