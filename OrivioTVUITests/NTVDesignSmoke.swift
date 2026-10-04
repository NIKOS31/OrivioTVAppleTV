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

        XCTAssertTrue(app.images["ntv.brand"].firstMatch.waitForExistence(timeout: 20))
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

        let addons = app.buttons["ntv.navigation.7"]
        remote.press(.up)
        XCTAssertTrue(focused(addons, timeout: 5), "Up from Settings should focus Addons.")

        // Live TV is enabled by default and sits above Addons.
        // Verify its focus when present rather than hiding an existing feature.
        let liveTV = app.buttons["ntv.navigation.4"]
        if liveTV.exists {
            remote.press(.up)
            XCTAssertTrue(focused(liveTV, timeout: 5), "Up from Addons should focus Live TV.")
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
        let focusedMovie = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.poster.movie.")).firstMatch
        for _ in 0..<4 {
            if focusedMovie.exists { break }
            remote.press(.down)
            if focusedMovie.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(focusedMovie.exists, "Down should move focus from the selectors into the movie grid.")
        let selectedPoster = app.buttons[focusedMovie.identifier]
        capture("ntv-films-real-catalog")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["ntv.detail.screen"].firstMatch.waitForExistence(timeout: 30),
                      "Selecting a poster must open the existing detail screen.")
        capture("ntv-film-detail")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ntv.catalog.movie.heading"].waitForExistence(timeout: 15))
        XCTAssertTrue(selectedPoster.exists, "Returning from details should retain the selected movie.")
        // Back from a later poster first returns to the grid's start; Back
        // from that start then opens the rail, matching the upstream behavior.
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
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
        for _ in 0..<3 {
            if series.hasFocus { break }
            remote.press(.menu)
            if focused(series, timeout: 2) { break }
        }
        XCTAssertTrue(focused(series, timeout: 8))
        app.terminate()
    }

    func testAddonsQRAndEnabledStatePersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-settingsTabDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        openAddonsFromSettings(app)

        let remote = XCUIRemote.shared
        let phone = app.buttons["ntv.addons.phone"]
        XCTAssertTrue(focused(phone, timeout: 8))
        remote.press(.select)
        let address = app.staticTexts["ntv.addons.phone.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 20), "The real LAN server must provide an address for the QR.")
        XCTAssertTrue(address.label.hasPrefix("http://"))
        XCTAssertTrue(app.descendants(matching: .any)["ntv.addons.phone.qr"].firstMatch.exists)
        capture("ntv-addons-phone-qr")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ntv.addons.heading"].waitForExistence(timeout: 8))
        XCTAssertTrue(focused(phone, timeout: 5), "Closing QR must restore its button.")

        // Reopening exercises listener cleanup and restart, rather than a mock QR.
        remote.press(.select)
        XCTAssertTrue(address.waitForExistence(timeout: 20))
        remote.press(.menu)
        XCTAssertTrue(focused(phone, timeout: 5))
        let management = app.buttons["ntv.addons.manage"]
        remote.press(.right)
        XCTAssertTrue(focused(management, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["ntv.addons.manage.screen"].firstMatch.waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ntv.addons.heading"].waitForExistence(timeout: 8))
        XCTAssertTrue(focused(management, timeout: 5))

        let focusedRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.addon.row.")).firstMatch
        for _ in 0..<4 {
            if focusedRow.exists { break }
            remote.press(.down)
        }
        XCTAssertTrue(focusedRow.exists)
        let rowID = focusedRow.identifier
        let row = app.buttons[rowID]
        let originalState = row.value as? String
        XCTAssertTrue(originalState == "Activé" || originalState == "Désactivé")
        remote.press(.select)
        let changedState = originalState == "Activé" ? "Désactivé" : "Activé"
        XCTAssertEqual(row.value as? String, changedState)
        app.terminate()

        app.launch()
        openAddonsFromSettings(app)
        let restoredRow = app.buttons[rowID]
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 8))
        XCTAssertEqual(restoredRow.value as? String, changedState, "Addon state must survive relaunch through the original store.")
        for _ in 0..<4 {
            if restoredRow.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(restoredRow.hasFocus)
        remote.press(.select)
        XCTAssertEqual(restoredRow.value as? String, originalState)
        capture("ntv-addons-installed")
        remote.press(.menu)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.7"], timeout: 5))
        capture("ntv-addons-sidebar-restored")
        app.terminate()
    }

    private func openAddonsFromSettings(_ app: XCUIApplication) {
        let settings = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        let remote = XCUIRemote.shared
        for _ in 0..<3 {
            if settings.hasFocus { break }
            remote.press(.menu)
            if focused(settings, timeout: 3) { break }
        }
        XCTAssertTrue(settings.hasFocus)
        remote.press(.up)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.7"], timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.addons.heading"].waitForExistence(timeout: 10))
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
