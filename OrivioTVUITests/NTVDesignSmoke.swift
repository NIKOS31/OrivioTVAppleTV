import XCTest

/// Exercises the actual tvOS remote and the existing navigation callbacks.
/// Navigation remains covered offline. The catalog journey additionally uses
/// the engine's default Cinemeta addon, exercising real generic catalog data.
final class NTVDesignSmoke: XCTestCase {
    func testBrandAndSidebarRoundTrip() {
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
        XCTAssertTrue(settings.hasFocus, "Back should restore focus to the active sidebar destination.")
        capture("ntv-sidebar-navigation")

        // Live TV is enabled by default and sits between Library and Settings.
        // Verify its focus when present rather than hiding an existing feature.
        let liveTV = app.buttons["ntv.navigation.4"]
        if liveTV.exists {
            remote.press(.up)
            XCTAssertTrue(focused(liveTV, timeout: 5), "Up from Settings should focus Live TV.")
        }
        remote.press(.up)
        XCTAssertTrue(focused(library, timeout: 5), "Up should reach Library in the left sidebar.")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.library.heading"].waitForExistence(timeout: 15))
        capture("ntv-library")

        remote.press(.menu)
        XCTAssertTrue(focused(library, timeout: 5), "Back from Library should restore its own tab.")
        XCTAssertTrue(app.staticTexts["ntv.library.heading"].exists)
        capture("ntv-library-focus-restored")
        app.terminate()
    }

    func testHomeMoviesAndSeriesJourney() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["ntv.home.heading"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ntv.home.spotlight"].waitForExistence(timeout: 80),
                      "Home should display a title supplied by the default addon.")
        capture("ntv-home-real-catalogs")

        let remote = XCUIRemote.shared
        let home = app.buttons["ntv.navigation.0"]
        remote.press(.menu)
        XCTAssertTrue(focused(home, timeout: 8))
        remote.press(.down)
        let movies = app.buttons["ntv.navigation.5"]
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.catalog.movie.heading"].waitForExistence(timeout: 15))
        let firstMovie = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 80), "Films should load real movie metadata.")
        for _ in 0..<4 {
            if firstMovie.hasFocus { break }
            remote.press(.down)
            if focused(firstMovie, timeout: 2) { break }
        }
        XCTAssertTrue(firstMovie.hasFocus)
        capture("ntv-films-real-catalog")
        remote.press(.select)
        XCTAssertTrue(app.otherElements["ntv.detail.screen"].waitForExistence(timeout: 30),
                      "Selecting a poster must open the existing detail screen.")
        capture("ntv-film-detail")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ntv.catalog.movie.heading"].waitForExistence(timeout: 15))
        XCTAssertTrue(firstMovie.exists, "Returning from details should retain the movie catalog.")
        remote.press(.menu)
        XCTAssertTrue(focused(movies, timeout: 8))
        remote.press(.down)
        let series = app.buttons["ntv.navigation.6"]
        XCTAssertTrue(focused(series, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.catalog.series.heading"].waitForExistence(timeout: 15))
        let firstSeries = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ntv.poster.series.")).firstMatch
        XCTAssertTrue(firstSeries.waitForExistence(timeout: 80), "Séries should load real series metadata.")
        XCTAssertFalse(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch.exists,
                       "The Séries page must not contain movie posters.")
        capture("ntv-series-real-catalog")
        remote.press(.menu)
        XCTAssertTrue(focused(series, timeout: 8))
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
