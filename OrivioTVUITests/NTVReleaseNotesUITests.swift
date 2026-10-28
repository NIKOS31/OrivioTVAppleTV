import XCTest

final class NTVReleaseNotesUITests: XCTestCase {
    func testAcknowledgedNotesCanBeReopenedFromAboutWithoutResettingAutomaticPresentation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvReleaseNotesDemo", "-ntvReleaseNotesReset"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let button = app.buttons["ntv.releaseNotes.continue"]
        func focused(_ element: XCUIElement) -> Bool {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
            return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
        }
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(focused(button))
        remote.press(.select)
        app.terminate()
        app.launchArguments = ["-settingsDemo", "-paneAbout"]
        app.launch()
        let reopen = app.buttons["ntv.settings.releaseNotes"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 20))
        remote.press(.right)
        XCTAssertTrue(focused(reopen), "The first About action must be reachable from the settings rail.")
        for attempt in 0..<2 {
            remote.press(.select)
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            XCTAssertTrue(focused(button))
            XCTAssertTrue(app.staticTexts["Nouveautés de nTV 51"].exists)
            XCTAssertTrue(app.scrollViews["ntv.releaseNotes.content"].exists)
            if attempt == 0 {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "ntv-release-notes-51-reopened-from-about"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                remote.press(.select)
            } else {
                remote.press(.menu)
            }
            XCTAssertTrue(focused(reopen), "Both Continue and Back must return to the persistent About action.")
            XCTAssertFalse(button.exists)
        }
        app.terminate()
        app.launchArguments = ["-homeDemo", "-ntvReleaseNotesDemo"]
        app.launch()
        XCTAssertFalse(button.waitForExistence(timeout: 8), "Manual reopening must not reset the acknowledged build.")
        XCTAssertTrue(app.buttons["ntv.navigation.0"].exists)
    }

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
        XCTAssertTrue(app.staticTexts["Nouveautés de nTV 51"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ntv-release-notes-51"
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
