import XCTest

final class NTVPlayerBarTests: XCTestCase {
    func testTimelineKeepsOneBarThroughPreviewCancelAndCommit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        var opening: XCUIElementSnapshot?
        for _ in 0..<10 {
            remote.press(.up)
            if let snapshot = try? play.snapshot() { opening = snapshot; break }
        }
        XCTAssertEqual(try XCTUnwrap(opening).label, "Pause")
        remote.press(.playPause)
        XCTAssertEqual(try play.snapshot().label, "Lecture")
        remote.press(.up)
        let timeline = app.buttons["ntv.player.timeline"]
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed)
        let transport = app.descendants(matching: .any)["ntv.player.transport"].firstMatch

        func matching(_ identifier: String, in snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            (snapshot.identifier == identifier ? [snapshot] : [])
                + snapshot.children.flatMap { matching(identifier, in: $0) }
        }
        let before = try transport.snapshot()
        let originalBar = try XCTUnwrap(matching("ntv.player.seek.progress", in: before).first).frame
        for confirm in [false, true] {
            remote.press(.select)
            remote.press(.right)
            // Presence, value and geometry share one fresh AX read before idle expiry.
            let preview = try transport.snapshot()
            XCTAssertEqual(preview.identifier, "ntv.player.transport")
            XCTAssertEqual(matching("ntv.player.timeline", in: preview).count, 1)
            XCTAssertTrue(matching("ntv.player.seek.progress", in: preview).isEmpty)
            let bars = matching("ntv.player.seek.preview", in: preview)
            XCTAssertEqual(bars.count, 1, "Adjusting must retain one timeline inside the existing transport.")
            let bar = try XCTUnwrap(bars.first)
            XCTAssertEqual(bar.frame.minY, originalBar.minY, accuracy: 1)
            XCTAssertEqual(bar.frame.minX, originalBar.minX, accuracy: 1)
            XCTAssertEqual(bar.frame.width, originalBar.width, accuracy: 1)
            let value = try XCTUnwrap(bar.value as? String)
            XCTAssertTrue(value.hasPrefix("Lecture "))
            XCTAssertTrue(value.contains(", cible "))
            remote.press(confirm ? .select : .menu)
            let settled = try transport.snapshot()
            XCTAssertEqual(matching("ntv.player.timeline", in: settled).count, 1)
            XCTAssertTrue(matching("ntv.player.seek.preview", in: settled).isEmpty)
            let settledBar = try XCTUnwrap(matching("ntv.player.seek.progress", in: settled).first)
            XCTAssertEqual(settledBar.frame.minY, originalBar.minY, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(matching("ntv.player.play", in: settled).first).label, "Lecture",
                           "Cancel and commit must preserve the paused transport.")
            let playFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [playFocused], timeout: 5), .completed)
            remote.press(.down)
            let infoFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: app.buttons["ntv.player.info"])
            XCTAssertEqual(XCTWaiter.wait(for: [infoFocused], timeout: 5), .completed,
                           "The restored information pill must expose its actual focus after cancel and commit.")
            remote.press(.up)
            let restoredPlayFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [restoredPlayFocused], timeout: 5), .completed)
            if !confirm {
                remote.press(.up)
                let timelineFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: timeline)
                XCTAssertEqual(XCTWaiter.wait(for: [timelineFocused], timeout: 5), .completed)
            }
        }
    }
}
