import XCTest

final class NTVReleaseNotesUITests: XCTestCase {
    func testReleaseNotesDismissAndStayDismissedAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvReleaseNotesDemo", "-ntvReleaseNotesReset"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let button = app.buttons["ntv.releaseNotes.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["Nouveautés de nTV 50"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ntv-release-notes-50"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIRemote.shared.press(.select)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        app.terminate()
        app.launchArguments = ["-homeDemo", "-ntvReleaseNotesDemo"]
        app.launch()
        // Give setup the same opportunity to present as on the first launch.
        XCTAssertFalse(app.buttons["ntv.releaseNotes.continue"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["ntv.navigation.0"].exists)
    }
}
