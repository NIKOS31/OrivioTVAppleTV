import XCTest

/// Exercises the actual tvOS remote and the existing navigation callbacks.
/// Does not depend on network artwork or on a configured third-party addon.
final class NTVDesignSmoke: XCTestCase {
    func testBrandAndTopNavigationRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-settingsTabDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()

        XCTAssertTrue(app.staticTexts["ntv.brand"].firstMatch.waitForExistence(timeout: 20))
        let settings = app.buttons["ntv.navigation.3"]
        let library = app.buttons["ntv.navigation.2"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))

        let remote = XCUIRemote.shared
        // Some settings panes consume the first Back to restore their category.
        for _ in 0..<3 {
            if settings.hasFocus { break }
            remote.press(.menu)
            if focused(settings, timeout: 3) { break }
        }
        XCTAssertTrue(settings.hasFocus, "Back should restore focus to the active top destination.")
        capture("ntv-top-navigation")

        remote.press(.left)
        XCTAssertTrue(focused(library, timeout: 5), "Left from Settings should focus Library.")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.library.heading"].waitForExistence(timeout: 15))
        capture("ntv-library")

        remote.press(.menu)
        XCTAssertTrue(focused(library, timeout: 5), "Back from Library should restore its own tab.")
        XCTAssertTrue(app.staticTexts["ntv.library.heading"].exists)
        capture("ntv-library-focus-restored")
        app.terminate()
    }

    private func focused(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"), object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
