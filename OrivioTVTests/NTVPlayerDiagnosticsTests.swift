import XCTest
@testable import OrivioTV

@MainActor
final class NTVPlayerDiagnosticsTests: XCTestCase {
    func testMissingEngineMetricsStayUnavailableInsteadOfReportingZero() {
        for engine in ["—", "VLC", "Dolby Vision direct"] {
            let snapshot = PlayerViewModel.DiagnosticsSnapshot(engine: engine)
            XCTAssertNil(snapshot.fps)
            XCTAssertNil(snapshot.droppedFrames)
            XCTAssertNil(snapshot.avSyncDiff)
            XCTAssertNil(snapshot.bitrateMbps)
            XCTAssertNil(snapshot.bufferSeconds)
            XCTAssertNil(snapshot.downloadedMB)
        }
    }

    func testBufferUsesAnAbsoluteReadHeadForBothDVAndKSPlayer() {
        for engine in ["Dolby Vision direct", "FFmpeg", "Natif"] {
            let snapshot = PlayerViewModel.DiagnosticsSnapshot(engine: engine, bufferedUpTo: 125, position: 120)
            XCTAssertEqual(snapshot.bufferSeconds, 5)
            XCTAssertNil(snapshot.droppedFrames, "Buffer availability does not imply frame metrics are available.")
            let seeking = PlayerViewModel.DiagnosticsSnapshot(engine: engine, bufferedUpTo: 125, position: 130)
            XCTAssertEqual(seeking.bufferSeconds, 0, "A measured empty buffer differs from an unavailable buffer.")
        }
        XCTAssertNil(PlayerViewModel.DiagnosticsSnapshot(bufferedUpTo: .nan, position: 120).bufferSeconds)
        XCTAssertNil(PlayerViewModel.DiagnosticsSnapshot(bufferedUpTo: 125, position: .infinity).bufferSeconds)
    }
}
