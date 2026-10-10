import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import OrivioTV

final class NTVPerformanceTests: XCTestCase {
    private actor Gate {
        private(set) var started: [String] = []
        private var held: [String: CheckedContinuation<Int, Error>] = [:]
        func mark(_ key: String) { started.append(key) }
        func run(_ key: String) async throws -> Int {
            started.append(key)
            return try await withCheckedThrowingContinuation { held[key] = $0 }
        }
        func release(_ key: String, value: Int = 1) { held.removeValue(forKey: key)?.resume(returning: value) }
        func fail(_ key: String) { held.removeValue(forKey: key)?.resume(throwing: FixtureFailure.failed) }
    }
    private enum FixtureFailure: Error { case failed, timeout }

    private func until(_ condition: () async -> Bool) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard clock.now < deadline else { throw FixtureFailure.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    private func expectCancellation<T: Sendable>(_ task: Task<T, Error>) async {
        do { _ = try await task.value; XCTFail("Cancelled waiter returned a value") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation result") }
    }

    func testSharedWindowBoundsActualWorkAcrossDifferentKeys() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 2), gate = Gate()
        let tasks = (0..<6).map { index in
            Task { try await pool.value(for: String(index)) { try await gate.run(String(index)) } }
        }
        try await until { await pool.activity.waiters == 6 }
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 2)
        XCTAssertEqual(activity.queued, 4)
        for batch in 0..<3 {
            try await until { await gate.started.count == (batch + 1) * 2 }
            let keys = await gate.started
            for key in keys.suffix(2) { await gate.release(key) }
        }
        for task in tasks { let value = try await task.value; XCTAssertEqual(value, 1) }
        let ended = await pool.activity
        XCTAssertEqual(ended.running, 0)
        XCTAssertEqual(ended.queued, 0)
        XCTAssertEqual(ended.waiters, 0)
    }

    func testConcurrentConsumersShareOneOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 4), gate = Gate()
        let first = Task { try await pool.value(for: "poster") { try await gate.run("poster") } }
        try await until { await gate.started.count == 1 }
        let second = Task { try await pool.value(for: "poster") { XCTFail("Duplicate work started"); return 99 } }
        try await until { await pool.activity.waiters == 2 }
        await gate.release("poster", value: 7)
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, 7); XCTAssertEqual(b, 7)
        let starts = await gate.started
        XCTAssertEqual(starts, ["poster"])
    }

    func testCancellingOneConsumerKeepsSharedWorkForTheOther() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let first = Task { try await pool.value(for: "poster") { try await gate.run("poster") } }
        try await until { await gate.started.count == 1 }
        let second = Task { try await pool.value(for: "poster") { XCTFail("Duplicate work started"); return 99 } }
        try await until { await pool.activity.waiters == 2 }
        first.cancel()
        await expectCancellation(first)
        let remaining = await pool.activity
        XCTAssertEqual(remaining.waiters, 1)
        await gate.release("poster", value: 8)
        let result = try await second.value
        XCTAssertEqual(result, 8)
    }

    func testQueuedCancellationNeverStartsTheAbandonedOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let held = Task { try await pool.value(for: "held") { try await gate.run("held") } }
        try await until { await gate.started.count == 1 }
        let abandoned = Task { try await pool.value(for: "abandoned") { XCTFail("Cancelled queued work started"); return 99 } }
        try await until { await pool.activity.queued == 1 }
        abandoned.cancel(); await expectCancellation(abandoned)
        await gate.release("held")
        _ = try await held.value
        let activity = await pool.activity
        XCTAssertEqual(activity.queued, 0)
        let starts = await gate.started
        XCTAssertEqual(starts, ["held"])
    }

    func testLastCancellationKeepsSlotUntilOldWorkStopsAndCannotPoisonReplacement() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        // This gate deliberately ignores cancellation, like an ImageIO call
        // already decoding. Releasing its waiter must not free its work slot.
        let old = Task { try await pool.value(for: "same-key") { try await gate.run("old") } }
        try await until { await gate.started.count == 1 }
        old.cancel(); await expectCancellation(old)
        let replacement = Task { try await pool.value(for: "same-key") { try await gate.run("new") } }
        try await until { await pool.activity.queued == 1 }
        let held = await pool.activity
        XCTAssertEqual(held.running, 1)
        let starts = await gate.started
        XCTAssertEqual(starts, ["old"])
        await gate.release("old", value: 100)
        try await until { await gate.started.count == 2 }
        await gate.release("new", value: 200)
        let result = try await replacement.value
        XCTAssertEqual(result, 200, "The old generation cannot deliver its result to a replacement.")
    }

    func testAlreadyCancelledConsumerDoesNotEnqueueWork() async {
        let pool = NTVSharedWorkPool<Int>(limit: 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pool.value(for: "unused") { XCTFail("Pre-cancelled work started"); return 1 }
        }
        await expectCancellation(task)
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 0)
        XCTAssertEqual(activity.waiters, 0)
    }

    func testLastWaiterCancellationReachesTheUnderlyingOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let task = Task {
            try await pool.value(for: "transfer") {
                await gate.mark("transfer")
                try await Task.sleep(for: .seconds(30))
                return 99
            }
        }
        try await until { await gate.started.count == 1 }
        task.cancel(); await expectCancellation(task)
        try await until { await pool.activity.running == 0 }
        let activity = await pool.activity
        XCTAssertEqual(activity.waiters, 0, "Cancelling the last waiter must also stop cancellable underlying work.")
    }

    func testFailedSharedWorkReleasesItsSlotAndCanBeRetried() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let first = Task { try await pool.value(for: "key") { try await gate.run("first") } }
        try await until { await gate.started.count == 1 }
        await gate.fail("first")
        do { _ = try await first.value; XCTFail("Expected failure") } catch is FixtureFailure {}
        let retry = try await pool.value(for: "key") { 42 }
        XCTAssertEqual(retry, 42)
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 0)
    }

    func testVisibleConsumerOvertakesQueuedPrefetchAndPromotesSharedKey() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let held = Task { try await pool.value(for: "held") { try await gate.run("held") } }
        try await until { await gate.started.count == 1 }
        let background = Task { try await pool.value(for: "background", priority: .background) { try await gate.run("background") } }
        try await until { await pool.activity.queued == 1 }
        let promoted = Task { try await pool.value(for: "promoted", priority: .background) { try await gate.run("promoted") } }
        try await until { await pool.activity.queued == 2 }
        let visible = Task { try await pool.value(for: "promoted") { XCTFail("Promotion duplicated work"); return 99 } }
        try await until { await pool.activity.waiters == 4 }
        await gate.release("held"); _ = try await held.value
        try await until { await gate.started.count == 2 }
        let starts = await gate.started
        XCTAssertEqual(starts, ["held", "promoted"])
        await gate.release("promoted", value: 10)
        _ = try await promoted.value; let visibleResult = try await visible.value
        XCTAssertEqual(visibleResult, 10)
        try await until { await gate.started.count == 3 }
        await gate.release("background"); _ = try await background.value
    }

    func testCancelledAddonSweepDoesNotStartItsRemainingItems() async throws {
        let gate = Gate()
        let task = Task {
            await boundedConcurrentMap(Array(0..<100), limit: 2) { index in
                (try? await gate.run(String(index))) ?? -1
            }
        }
        try await until { await gate.started.count == 2 }
        task.cancel()
        await gate.release("0"); await gate.release("1")
        let values = await task.value
        XCTAssertTrue(values.isEmpty, "A cancelled sweep cannot publish a partial array with shifted indices.")
        let starts = await gate.started
        XCTAssertEqual(starts.count, 2, "No refill of a cancelled sweep.")
    }

    func testAlreadyCancelledSweepStartsNothing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await boundedConcurrentMap([1, 2, 3], limit: 2) { _ in XCTFail("Cancelled sweep started"); return 1 }
        }
        let values = await task.value
        XCTAssertTrue(values.isEmpty)
    }

    func testBoundedSweepPreservesOrderWhenCompletionOrderDiffers() async throws {
        let gate = Gate()
        let task = Task {
            await boundedConcurrentMap([0, 1, 2], limit: 3) { index in
                (try? await gate.run(String(index))) ?? -1
            }
        }
        try await until { await gate.started.count == 3 }
        for index in [2, 0, 1] { await gate.release(String(index), value: index * 10) }
        let values = await task.value
        XCTAssertEqual(values, [0, 10, 20])
    }

    @MainActor
    private func jpeg(width: Int = 2048, height: Int = 1024, orientation: Int = 1) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testArtworkDecodeRespectsPixelBudgetAndOrientation() async throws {
        let data = try await jpeg(orientation: 6)
        let image = try XCTUnwrap(ImageCache.decodeDownsampled(data, budget: 340))
        XCTAssertEqual(image.cgImage?.width, 170)
        XCTAssertEqual(image.cgImage?.height, 340)
        XCTAssertEqual(image.imageOrientation, .up)
    }

    func testArtworkDecodeRejectsInvalidBytesAndInvalidBudgets() async throws {
        XCTAssertNil(ImageCache.decodeDownsampled(Data("invalid image".utf8), budget: 340))
        let data = try await jpeg(width: 24, height: 12)
        XCTAssertNil(ImageCache.decodeDownsampled(data, budget: 0))
        XCTAssertNil(ImageCache.decodeDownsampled(data, budget: -1))
        let small = try XCTUnwrap(ImageCache.decodeDownsampled(data, budget: 128))
        XCTAssertEqual(small.cgImage?.width, 24, "A bounded decode must not enlarge a small original.")
    }

    @MainActor
    func testArtworkBucketsNeverExceedExplicitHardCap() {
        XCTAssertEqual(RemoteImage.pixelBudget(maxDimension: nil, maxPixels: 2560), 2560)
        XCTAssertEqual(RemoteImage.pixelBudget(maxDimension: 5000, maxPixels: 512), 512)
        XCTAssertLessThanOrEqual(RemoteImage.pixelBudget(maxDimension: 300, maxPixels: 512) ?? 9999, 512)
    }

    func testConcurrentArtworkPreparationReusesTheSameDecodedObject() async throws {
        let data = try await jpeg(), key = "ntv-fixture-\(UUID())#340"
        async let a = ImageCache.shared.preparedImage(data, budget: 340, memoryKey: key)
        async let b = ImageCache.shared.preparedImage(data, budget: 340, memoryKey: key)
        let (first, second) = try await (a, b)
        let image = try XCTUnwrap(first), reused = try XCTUnwrap(second)
        XCTAssertTrue(image === reused, "Two views must share a single prepared rendition.")
        XCTAssertEqual(image.cgImage?.width, 340)
    }

    func testArtworkPreparationKeepsSmallAndLargeRenditionsSeparate() async throws {
        let data = try await jpeg(), key = "ntv-fixture-\(UUID())"
        let small = try await ImageCache.shared.preparedImage(data, budget: 240, memoryKey: key + "#240")
        let large = try await ImageCache.shared.preparedImage(data, budget: 680, memoryKey: key + "#680")
        XCTAssertEqual(small?.cgImage?.width, 240)
        XCTAssertEqual(large?.cgImage?.width, 680)
        XCTAssertFalse(small === large)
    }
}
