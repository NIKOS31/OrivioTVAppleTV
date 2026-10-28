import XCTest
import Combine
@testable import OrivioTV

@MainActor
final class NTVPlayerTouchTests: XCTestCase {
    private func playingFixture() async throws -> PlayerViewModel {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ntv-player-fixture", withExtension: "mp4"))
        let stream = Stream(name: "Local fixture", title: nil, description: nil,
                            url: url.absoluteString, infoHash: nil, behaviorHints: nil)
        let request = PlaybackRequest(meta: MetaItem(id: "ntv-touch-test", type: "collection", name: "Local fixture"),
                                      video: nil, entry: StreamEntry(addonName: "Fixture", stream: stream),
                                      allEntries: [], resumePosition: nil)
        var settings = PlayerSettings.default
        settings.playerEngine = .native
        let model = PlayerViewModel(request: request, addonManager: AddonManager(startRefresh: false),
                                    progressStore: ProgressStore(), settings: settings)
        model.usesNTVControls = true
        let ready = expectation(description: "Production player starts the bundled fixture")
        let observation = model.$hasStartedPlayback.combineLatest(model.clock.$duration)
            .filter { $0.0 && $0.1 > 300 }.first().sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [ready], timeout: 20)
        guard model.hasStartedPlayback, model.clock.duration > 300 else {
            model.teardown()
            return try XCTUnwrap(nil as PlayerViewModel?, "The real player fixture must start before testing touch input.")
        }
        return model
    }

    private func drag(_ model: PlayerViewModel, points: CGFloat, cancelled: Bool = false) {
        model.remoteTouchBegan()
        model.remoteTouchMoved(dx: points, dy: 0)
        model.remoteTouchEnded(dx: points, dy: 0, cancelled: cancelled)
    }

    func testBarTouchLiftKeepsPreviewAcrossContactsAndIdleUntilCancel() async throws {
        let model = try await playingFixture()
        defer { model.teardown() }
        model.showControls()
        model.controlsFocusOnBar = true
        let session = model.controlsSession
        drag(model, points: 400)
        let first = try XCTUnwrap(model.clock.scrubTarget)
        XCTAssertTrue(model.isScrubbing, "Lifting a finger on the bar must not validate the proposed position.")
        XCTAssertEqual(model.controlsSession, session, "A lift must not reopen transport and reset its focus to Play.")
        try await Task.sleep(for: .milliseconds(6300))
        XCTAssertTrue(model.isScrubbing, "The bar preview must survive both the five-second hide and six-second scrub timers.")
        XCTAssertEqual(model.clock.scrubTarget, first)
        drag(model, points: 200)
        let second = try XCTUnwrap(model.clock.scrubTarget)
        XCTAssertGreaterThan(second, first, "The next contact must continue from the previous preview target.")
        XCTAssertLessThan(model.clock.position, second - 5, "Previewing must not seek the real player.")
        model.cancelScrub()
        XCTAssertFalse(model.isScrubbing)
        XCTAssertNil(model.clock.scrubTarget)
        XCTAssertEqual(model.overlay, .controls)
        XCTAssertTrue(model.isPlaying, "Cancelling a running preview must keep playback running.")
        XCTAssertLessThan(model.clock.position, second - 5)
    }

    func testBarTouchCommitKeepsPausedIntent() async throws {
        let model = try await playingFixture()
        defer { model.teardown() }
        model.togglePlayPause()
        XCTAssertFalse(model.isPlaying)
        model.showControls()
        model.controlsFocusOnBar = true
        drag(model, points: 400)
        let target = try XCTUnwrap(model.clock.scrubTarget)
        XCTAssertTrue(model.isScrubbing)
        XCTAssertFalse(model.isPlaying)
        model.commitScrub()
        XCTAssertFalse(model.isScrubbing)
        XCTAssertNil(model.clock.scrubTarget)
        XCTAssertEqual(model.clock.position, target, accuracy: 0.1)
        XCTAssertFalse(model.isPlaying, "Confirming from pause must not force playback.")
        XCTAssertEqual(model.overlay, .controls)
    }

    func testBareVideoDragStillCommitsOnLift() async throws {
        let model = try await playingFixture()
        defer { model.teardown() }
        model.hideControls()
        model.controlsFocusOnBar = false
        model.remoteTouchBegan()
        model.remoteTouchMoved(dx: 400, dy: 0)
        let target = try XCTUnwrap(model.clock.scrubTarget)
        model.remoteTouchEnded(dx: 400, dy: 0, cancelled: false)
        XCTAssertFalse(model.isScrubbing, "A discreet gesture on bare video keeps its existing release-to-seek behavior.")
        XCTAssertNil(model.clock.scrubTarget)
        XCTAssertEqual(model.clock.position, target, accuracy: 0.1)
        XCTAssertEqual(model.overlay, .controls)
    }

    func testCancelledBarContactDiscardsPreviewWithoutSeeking() async throws {
        let model = try await playingFixture()
        defer { model.teardown() }
        model.showControls()
        model.controlsFocusOnBar = true
        model.remoteTouchBegan()
        model.remoteTouchMoved(dx: 400, dy: 0)
        let target = try XCTUnwrap(model.clock.scrubTarget)
        model.remoteTouchEnded(dx: 400, dy: 0, cancelled: true)
        XCTAssertFalse(model.isScrubbing)
        XCTAssertNil(model.clock.scrubTarget)
        XCTAssertLessThan(model.clock.position, target - 5)
        XCTAssertEqual(model.overlay, .controls)
    }

    func testOtherTransportKeepsItsExistingIdleCancellation() async throws {
        let model = try await playingFixture()
        defer { model.teardown() }
        model.usesNTVControls = false
        model.showControls()
        model.beginScrub()
        drag(model, points: 400)
        XCTAssertTrue(model.isScrubbing)
        try await Task.sleep(for: .milliseconds(6300))
        XCTAssertFalse(model.isScrubbing, "The nTV bar change must not disable other transports’ idle cancellation.")
        XCTAssertNil(model.clock.scrubTarget)
    }
}
