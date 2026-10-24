import AVFoundation
import KSPlayer
import UIKit
import XCTest

@MainActor
final class NTVSeekCompletionTests: XCTestCase {
    private func fixture() -> (KSPlayerLayer, NTVSeekFixturePlayer) {
        let previous = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = NTVSeekFixturePlayer.self
        defer { KSOptions.firstPlayerType = previous }
        let options = NTVSeekFixtureOptions()
        options.registerRemoteControll = false
        let layer = KSPlayerLayer(url: URL(fileURLWithPath: "/ntv-seek-fixture.mp4"),
                                  isAutoPlay: false, options: options)
        return (layer, layer.player as! NTVSeekFixturePlayer)
    }

    func testPauseRetiresPendingSeekAutoplayAndCompletion() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        layer.play()
        var delivered = false
        layer.seek(time: 40, autoPlay: true) { _ in delivered = true }
        layer.pause()
        player.completeSeek(0, finished: true)
        XCTAssertEqual(player.playCalls, 1)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(layer.state, .paused)
        XCTAssertFalse(delivered, "An obsolete callback must not trigger a caller's playback recovery.")
    }

    func testAutoplaySeekFromPauseStartsOnlyAfterItsOwnSuccessfulCompletion() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        layer.pause()
        var results: [Bool] = []
        layer.seek(time: 40, autoPlay: true) { results.append($0) }
        XCTAssertEqual(player.playCalls, 0)
        player.completeSeek(0, finished: true)
        XCTAssertEqual(player.playCalls, 1)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(results, [true])
    }

    func testNewerSeekRetiresTheEarlierSeekEvenWhenItFinishesLast() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        var oldDelivered = false
        var results: [Bool] = []
        layer.seek(time: 40, autoPlay: true) { _ in oldDelivered = true }
        layer.seek(time: 80, autoPlay: false) { results.append($0) }
        player.completeSeek(1, finished: true)
        player.completeSeek(0, finished: true)
        XCTAssertFalse(oldDelivered)
        XCTAssertEqual(results, [true])
        XCTAssertEqual(player.playCalls, 0)
    }

    func testStopRetiresPendingSeek() {
        let (layer, player) = fixture()
        var delivered = false
        layer.seek(time: 40, autoPlay: true) { _ in delivered = true }
        layer.stop()
        player.completeSeek(0, finished: true)
        XCTAssertFalse(delivered)
        XCTAssertEqual(player.playCalls, 0)
        XCTAssertEqual(layer.state, .initialized)
    }

    func testPlayerReplacementRetiresPendingSeek() {
        let (layer, oldPlayer) = fixture()
        defer { layer.stop() }
        var delivered = false
        layer.seek(time: 40, autoPlay: true) { _ in delivered = true }
        let replacement = NTVSeekFixturePlayer(url: layer.url, options: layer.options)
        layer.player = replacement
        oldPlayer.completeSeek(0, finished: true)
        XCTAssertFalse(delivered)
        XCTAssertEqual(oldPlayer.playCalls, 0)
        XCTAssertEqual(replacement.playCalls, 0)
    }

    func testLateFinishFromReplacedPlayerDoesNotRetireTheNewPlayersSeek() {
        let (layer, oldPlayer) = fixture()
        defer { layer.stop() }
        let replacement = NTVSeekFixturePlayer(url: layer.url, options: layer.options)
        layer.player = replacement
        var results: [Bool] = []
        layer.seek(time: 80, autoPlay: false) { results.append($0) }
        layer.finish(player: oldPlayer, error: nil)
        replacement.completeSeek(0, finished: true)
        XCTAssertEqual(results, [true])
        XCTAssertEqual(replacement.playCalls, 0)
    }

    func testSettingSourceAgainRetiresPendingSeekOnTheSamePlayer() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        let previous = KSOptions.firstPlayerType
        KSOptions.firstPlayerType = NTVSeekFixturePlayer.self
        defer { KSOptions.firstPlayerType = previous }
        var delivered = false
        layer.seek(time: 40, autoPlay: true) { _ in delivered = true }
        layer.set(url: layer.url, options: layer.options)
        player.completeSeek(0, finished: true)
        XCTAssertTrue(layer.player === player)
        XCTAssertFalse(delivered)
        XCTAssertEqual(player.playCalls, 0)
    }

    func testFailedCurrentSeekIsDeliveredWithoutAutoplay() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        var results: [Bool] = []
        layer.seek(time: 40, autoPlay: true) { results.append($0) }
        player.completeSeek(0, finished: false)
        XCTAssertEqual(results, [false])
        XCTAssertEqual(player.playCalls, 0)
    }

    func testPauseAlsoRetiresTheReplaySeek() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        layer.finish(player: player, error: nil)
        layer.play()
        layer.pause()
        player.completeSeek(0, finished: true)
        XCTAssertEqual(player.playCalls, 0)
        XCTAssertEqual(layer.state, .paused)
    }

    func testInvalidSeekReturnsOnceWithoutReachingTheEngine() {
        let (layer, player) = fixture()
        defer { layer.stop() }
        for time in [Double.nan, .infinity, -.infinity] {
            var results: [Bool] = []
            layer.seek(time: time, autoPlay: true) { results.append($0) }
            XCTAssertEqual(results, [false])
        }
        XCTAssertEqual(player.seekCount, 0)
        XCTAssertEqual(player.playCalls, 0)
    }
}

private final class NTVSeekFixtureOptions: KSOptions {
    override func playerLayerDeinit() {}
}

private final class NTVSeekFixturePlayer: MediaPlayerProtocol {
    weak var delegate: MediaPlayerDelegate?
    let duration: TimeInterval = 600
    let fileSize: Double = 0
    let naturalSize: CGSize = .zero
    let chapters: [Chapter] = []
    let currentPlaybackTime: TimeInterval = 0
    let view: UIView? = nil
    let playableTime: TimeInterval = 600
    let isReadyToPlay = true
    var playbackState: MediaPlaybackState = .paused
    let loadState: MediaLoadState = .playable
    var isPlaying: Bool { playbackState == .playing }
    let seekable = true
    var isMuted = false
    var allowsExternalPlayback = false
    var usesExternalPlaybackWhileExternalScreenIsActive = false
    let isExternalPlaybackActive = false
    var playbackRate: Float = 1
    var playbackVolume: Float = 1
    var contentMode: UIViewContentMode = .scaleAspectFit
    let subtitleDataSouce: SubtitleDataSouce? = nil
    var playbackCoordinator: AVPlaybackCoordinator { AVPlayer().playbackCoordinator }
    let pipController: KSPictureInPictureController? = nil
    let dynamicInfo: DynamicInfo? = nil
    private(set) var playCalls = 0
    private var completions: [((Bool) -> Void)?] = []
    var seekCount: Int { completions.count }

    init(url: URL, options: KSOptions) {}
    func replace(url: URL, options: KSOptions) { playbackState = .paused }
    func prepareToPlay() {}
    func shutdown() { playbackState = .stopped }
    func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        playbackState = .seeking
        completions.append(completion)
    }
    func completeSeek(_ index: Int, finished: Bool) {
        let completion = completions[index]
        completions[index] = nil
        completion?(finished)
    }
    func play() { playCalls += 1; playbackState = .playing }
    func pause() { playbackState = .paused }
    func enterBackground() {}
    func enterForeground() {}
    func thumbnailImageAtCurrentTime() async -> CGImage? { nil }
    func tracks(mediaType: AVMediaType) -> [MediaPlayerTrack] { [] }
    func select(track: some MediaPlayerTrack) {}
}
