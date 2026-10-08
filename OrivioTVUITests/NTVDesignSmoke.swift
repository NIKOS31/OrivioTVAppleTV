import XCTest

/// Exercises the actual tvOS remote and the existing navigation callbacks.
/// Navigation remains covered offline. The catalog journey additionally uses
/// the engine's default Cinemeta addon, exercising real generic catalog data.
final class NTVDesignSmoke: XCTestCase {
    func testLaunchLogoIsCenteredAndDoesNotReplayOnForeground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvLaunchTest"]
        app.launch()
        let logo = app.images["ntv.launch.logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(logo.frame.midX, screen.midX, accuracy: 2)
        XCTAssertEqual(logo.frame.midY, screen.midY, accuracy: 2)
        XCTAssertGreaterThan(logo.frame.width, 250)
        XCTAssertTrue(screen.contains(logo.frame))
        XCTAssertFalse(app.staticTexts["Bienvenue sur nTV"].exists,
                       "Onboarding must not obscure the launch mark.")
        capture("ntv-launch-centered")
        XCUIRemote.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertFalse(logo.exists, "Returning to the foreground cannot replay the introduction.")
        app.terminate()
        app.launch()
        XCTAssertTrue(logo.waitForExistence(timeout: 5), "A fresh process presents the mark again.")
        app.terminate()
    }

    func testTwitchConnectionAndFollowedChannelsFromSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo", "-ntvTwitchDemo"]
        app.launch()
        let remote = XCUIRemote.shared
        let integration = app.buttons["ntv.settings.category.integration"]
        XCTAssertTrue(integration.waitForExistence(timeout: 20))
        for _ in 0..<8 {
            if integration.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(integration, timeout: 5))
        remote.press(.select)
        remote.press(.right)
        let entry = app.buttons["ntv.integration.twitch"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        // Entering a two-column pane preserves the remote's vertical position.
        // Reach the first service naturally instead of assuming Right lands there.
        for _ in 0..<7 {
            if entry.hasFocus { break }
            remote.press(.up)
        }
        XCTAssertTrue(focused(entry, timeout: 5))
        remote.press(.select)
        let connect = app.buttons["ntv.twitch.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertTrue(focused(connect, timeout: 5))
        remote.press(.select)
        let code = app.staticTexts["ntv.twitch.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.label, "NTVTEST")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(code.frame))
        capture("ntv-twitch-device-code")
        let stream = app.descendants(matching: .any)["ntv.twitch.stream.fixture-live"].firstMatch
        XCTAssertTrue(stream.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ntv.twitch.disconnect"].exists)
        capture("ntv-twitch-followed")
        XCTAssertTrue(focused(app.buttons["ntv.twitch.followed"], timeout: 5))
        remote.press(.right)
        XCTAssertTrue(focused(app.buttons["ntv.twitch.search"], timeout: 5))
        remote.press(.select)
        let query = app.textFields["ntv.twitch.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(query.frame))
        capture("ntv-twitch-search")
        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["ntv.settings.heading"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSettingsWorkspaceAndProfileCustomization() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo"]
        app.launch()
        let heading = app.staticTexts["ntv.settings.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        XCTAssertEqual(heading.label, "Réglages")
        let navigation = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(heading.frame.minY, navigation.frame.maxY + 8, "The page title must clear the floating menu.")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(heading.frame))
        XCTAssertTrue(screen.contains(app.buttons["ntv.settings.customize"].frame))
        capture("ntv-settings-workspace-fr")

        let remote = XCUIRemote.shared
        for _ in 0..<3 {
            if navigation.hasFocus { break }
            remote.press(.menu)
            if focused(navigation, timeout: 3) { break }
        }
        XCTAssertTrue(navigation.hasFocus)
        remote.press(.right)
        let profile = app.buttons["ntv.navigation.profile"]
        XCTAssertTrue(focused(profile, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Qui regarde ?"].waitForExistence(timeout: 10))
        remote.press(.down)
        let manage = app.buttons["ntv.profiles.manage"]
        XCTAssertTrue(focused(manage, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Gérer les profils"].waitForExistence(timeout: 10))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.profile.edit.heading"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ntv.profile.avatar.ntv.glasses"].exists)
        capture("ntv-profile-real-entry")
        let done = app.buttons["ntv.profile.done"]
        for _ in 0..<3 {
            if done.hasFocus { break }
            remote.press(.up)
        }
        XCTAssertTrue(focused(done, timeout: 5), "Done must be reachable from the avatar grid.")
        XCTAssertTrue(screen.contains(done.frame), "The Done control remains visible above scrolling settings.")
        capture("ntv-profile-done-focused")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Gérer les profils"].waitForExistence(timeout: 5), "Selecting Done must close the editor.")
        XCTAssertFalse(app.staticTexts["ntv.profile.edit.heading"].exists)
        app.terminate()
    }

    func testProfileCharacterPersistsOffline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvProfileDemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ntv.profile.edit.heading"].waitForExistence(timeout: 20))
        let remote = XCUIRemote.shared
        let initial = app.buttons["ntv.profile.avatar.initial"]
        let focusedAvatar = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.profile.avatar.")).firstMatch
        XCTAssertTrue(focusedAvatar.waitForExistence(timeout: 10), "The editor must initially focus the selected character.")
        for _ in 0..<4 {
            if initial.hasFocus { break }
            remote.press(.left)
        }
        XCTAssertTrue(focused(initial, timeout: 5))
        remote.press(.right)
        XCTAssertTrue(focused(app.buttons["ntv.profile.avatar.ntv.glasses"], timeout: 5))
        remote.press(.right)
        let curls = app.buttons["ntv.profile.avatar.ntv.curls"]
        XCTAssertTrue(focused(curls, timeout: 5))
        remote.press(.select)
        XCTAssertEqual(curls.value as? String, "Sélectionné")
        capture("ntv-profile-characters")
        app.terminate()
        app.launch()
        XCTAssertTrue(curls.waitForExistence(timeout: 20))
        XCTAssertEqual(curls.value as? String, "Sélectionné", "The bundled character must survive relaunch without an account.")
        XCTAssertTrue(focused(curls, timeout: 5))
        remote.press(.left)
        remote.press(.left)
        XCTAssertTrue(focused(initial, timeout: 5))
        remote.press(.select)
        let done = app.buttons["ntv.profile.done"]
        for _ in 0..<3 {
            if done.hasFocus { break }
            remote.press(.up)
        }
        XCTAssertTrue(focused(done, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(app.textFields["ntv.profile.name"], timeout: 5))
        remote.press(.up)
        XCTAssertTrue(focused(done, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.home.heading"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(initial.waitForExistence(timeout: 20))
        XCTAssertNotEqual(curls.value as? String, "Sélectionné", "Choosing initials must replace the previous character.")
        app.terminate()
    }

    func testProfileGridSecondRowPersistsOffline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvProfileDemo"]
        app.launch()
        let remote = XCUIRemote.shared
        let initial = app.buttons["ntv.profile.avatar.initial"]
        XCTAssertTrue(initial.waitForExistence(timeout: 20))
        XCTAssertTrue(focused(initial, timeout: 10))
        remote.press(.down)
        XCTAssertTrue(focused(app.buttons["ntv.profile.avatar.ntv.cap"], timeout: 5), "Down must reach the second row of characters.")
        for _ in 0..<5 { remote.press(.right) }
        let last = app.buttons["ntv.profile.avatar.ntv.roundglasses"]
        XCTAssertTrue(focused(last, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(last.frame), "The last character must be visible within the TV screen.")
        remote.press(.select)
        XCTAssertEqual(last.value as? String, "Sélectionné")
        capture("ntv-profile-twelve-characters")
        app.terminate()
        app.launch()
        XCTAssertTrue(last.waitForExistence(timeout: 20))
        XCTAssertEqual(last.value as? String, "Sélectionné")
        XCTAssertTrue(focused(last, timeout: 10))
        remote.press(.up)
        XCTAssertTrue(focused(app.buttons["ntv.profile.avatar.ntv.silver"], timeout: 5))
        for _ in 0..<5 { remote.press(.left) }
        XCTAssertTrue(focused(initial, timeout: 5))
        remote.press(.select)
        app.terminate()
    }

    func testTopMenuRemoteRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo"]
        app.launch()
        let settings = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        let remote = XCUIRemote.shared
        for _ in 0..<3 {
            if settings.hasFocus { break }
            remote.press(.menu)
            if focused(settings, timeout: 3) { break }
        }
        XCTAssertTrue(settings.hasFocus)
        remote.press(.left)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.7"], timeout: 5))
        remote.press(.left)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.1"], timeout: 5))
        remote.press(.left)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.4"], timeout: 5))
        remote.press(.left)
        let library = app.buttons["ntv.navigation.2"]
        XCTAssertTrue(focused(library, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.library.heading"].waitForExistence(timeout: 15))
        remote.press(.menu)
        XCTAssertTrue(focused(library, timeout: 5), "Back must restore the selected top tab.")
        capture("ntv-top-glass-navigation")
        let screen = app.windows.firstMatch.frame
        for id in [0, 1, 2, 3, 4, 5, 6, 7] {
            let button = app.buttons["ntv.navigation.\(id)"]
            XCTAssertTrue(screen.contains(button.frame), "Top tab \(id) must stay within the TV screen.")
        }
        for _ in 0..<3 { remote.press(.left) }
        let home = app.buttons["ntv.navigation.0"]
        XCTAssertTrue(focused(home, timeout: 5))
        remote.press(.select)
        let heading = app.staticTexts["ntv.home.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ntv.home.spotlight"].waitForExistence(timeout: 80))
        XCTAssertGreaterThan(heading.frame.minY, home.frame.maxY + 8,
                             "Home must reserve a visible band below the floating top menu.")
        XCTAssertTrue(screen.contains(heading.frame))
        capture("ntv-home-top-menu-clearance")
        let canvas = app.descendants(matching: .any)["ntv.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(canvas.frame.minY, screen.minY, accuracy: 2, "Artwork must reach behind the floating menu.")
        XCTAssertEqual(canvas.frame.width, screen.width, accuracy: 2)
        remote.press(.menu)
        XCTAssertTrue(focused(home, timeout: 5))
        remote.press(.right)
        let movies = app.buttons["ntv.navigation.5"]
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.select)
        let firstMovie = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 80))
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).allElementsBoundByIndex
        let row = posters.filter { abs($0.frame.minY - firstMovie.frame.minY) < 30 }
        XCTAssertLessThanOrEqual(firstMovie.frame.minX, screen.minX + 70, "The grid must use the screen width.")
        XCTAssertGreaterThanOrEqual(row.map { $0.frame.maxX }.max() ?? 0, screen.maxX - 80,
                                    "The last column must reach the right content margin.")
        capture("ntv-films-full-width")
        app.terminate()
    }

    func testPlayerTimelineCancelAndCommit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        // A fresh video starts without chrome. Open it as a viewer does;
        // early Up presses are ignored while the local fixture is loading.
        for _ in 0..<10 {
            if play.exists { break }
            remote.press(.up)
            if play.waitForExistence(timeout: 2) { break }
        }
        let opened = play.exists
        if !opened { capture("ntv-player-startup-failure") }
        XCTAssertTrue(opened, "The local video fixture must open nTV controls.")
        XCTAssertTrue(focused(play, timeout: 8))
        let quickPosition = app.staticTexts["ntv.player.position"].firstMatch
        XCTAssertTrue(quickPosition.waitForExistence(timeout: 5))
        let beforeQuickSeek = quickPosition.label
        remote.press(.right)
        XCTAssertNotEqual(quickPosition.label, beforeQuickSeek, "Right from the compact play control must perform a quick skip.")
        if play.label == "Pause" { remote.press(.playPause) }
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        remote.press(.up)
        let timeline = app.buttons["ntv.player.timeline"]
        XCTAssertTrue(focused(timeline, timeout: 5))
        remote.press(.right)
        let position = app.staticTexts["ntv.player.position"].firstMatch
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        let first = position.label
        remote.press(.right)
        XCTAssertNotEqual(position.label, first, "Right must move the seek preview before committing.")
        capture("ntv-player-seek-preview")
        remote.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        XCTAssertEqual(play.label, "Lecture", "Cancelling a seek must keep a paused video paused.")
        XCTAssertTrue(focused(play, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(app.buttons["ntv.player.info"], timeout: 5), "The information pill must remain reachable below the bar.")
        remote.press(.up)
        XCTAssertTrue(focused(play, timeout: 5))
        remote.press(.up)
        XCTAssertTrue(focused(timeline, timeout: 5))
        remote.press(.up)
        XCTAssertTrue(focused(app.buttons["ntv.player.video"], timeout: 5), "The floating tools must remain reachable above the bar.")
        remote.press(.down)
        XCTAssertTrue(focused(timeline, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        remote.press(.right)
        remote.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        // Seeking completes asynchronously. Verify the resulting transport
        // state after completion rather than during the demuxer transition.
        let playbackResumed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Pause"), object: play
        )
        XCTAssertEqual(XCTWaiter.wait(for: [playbackResumed], timeout: 8), .completed,
                       "Committing the seek must resume playback.")
        let resumedPosition = position.label
        let clockAdvanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", resumedPosition), object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [clockAdvanced], timeout: 5), .completed,
                       "The real playback clock must advance after committing, not just change the button label.")
        let screen = app.windows.firstMatch.frame
        for element in [play, timeline, app.staticTexts["ntv.player.heading"], app.buttons["ntv.player.info"]] {
            XCTAssertTrue(screen.contains(element.frame), "The minimal transport must stay within the TV screen.")
        }
        capture("ntv-player-controls")
        app.terminate()
    }

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
        XCTAssertGreaterThan(app.staticTexts["ntv.home.heading"].frame.minX,
                             app.buttons["ntv.navigation.0"].frame.maxX + 8,
                             "Home must leave horizontal space beside the collapsed left menu.")
        capture("ntv-home-real-catalogs")

        let remote = XCUIRemote.shared
        let home = app.buttons["ntv.navigation.0"]
        let homePoster = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.home.poster.")).firstMatch
        for _ in 0..<4 {
            if homePoster.exists { break }
            remote.press(.down)
            if homePoster.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(homePoster.exists, "Home posters must be reachable from the spotlight.")
        let homeID = homePoster.identifier.components(separatedBy: ".").dropFirst(4).joined(separator: ".")
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.home.backdrop", contentID: homeID))
        capture("ntv-home-focus-backdrop")
        for _ in 0..<3 {
            if home.hasFocus { break }
            remote.press(.menu)
            if focused(home, timeout: 2) { break }
        }
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
        let initialMovieID = focusedMovie.identifier
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(initialMovieID.dropFirst("ntv.poster.movie.".count))))
        remote.press(.right)
        XCTAssertTrue(focusedMovie.waitForExistence(timeout: 5))
        XCTAssertNotEqual(focusedMovie.identifier, initialMovieID, "Right must select another movie without opening details.")
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(focusedMovie.identifier.dropFirst("ntv.poster.movie.".count))))
        remote.press(.left)
        XCTAssertTrue(focused(app.buttons[initialMovieID], timeout: 5))
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(initialMovieID.dropFirst("ntv.poster.movie.".count))),
                      "Returning left must restore this movie's backdrop, never a stale pending title.")
        let selectedPoster = app.buttons[focusedMovie.identifier]
        capture("ntv-films-real-catalog")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["ntv.detail.screen"].firstMatch.waitForExistence(timeout: 30),
                      "Selecting a poster must open the existing detail screen.")
        capture("ntv-film-detail")
        let play = app.buttons["ntv.detail.play"]
        XCTAssertTrue(focused(play, timeout: 8), "The existing Play control must keep opening focus.")
        XCTAssertEqual(play.label, "Regarder")
        let sources = app.buttons["ntv.detail.sources"]
        remote.press(.right)
        XCTAssertTrue(focused(sources, timeout: 5), "Sources must be directly reachable beside Play.")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.sources.heading"].waitForExistence(timeout: 15))
        let openAddons = app.buttons["ntv.sources.addons"]
        XCTAssertTrue(openAddons.waitForExistence(timeout: 60), "With no stream addon installed, offer a real route to Addons.")
        XCTAssertTrue(app.descendants(matching: .any)["ntv.sources.empty"].firstMatch.exists)
        capture("ntv-sources-empty-recovery")
        for _ in 0..<4 {
            if openAddons.hasFocus { break }
            remote.press(.down)
            if focused(openAddons, timeout: 2) { break }
        }
        XCTAssertTrue(openAddons.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.addons.heading"].waitForExistence(timeout: 15))
        remote.press(.menu)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.7"], timeout: 8))
        // Addons are another tab: the Films stack must retain its source page.
        for _ in 0..<8 {
            if movies.hasFocus { break }
            remote.press(.up)
            if focused(movies, timeout: 1) { break }
        }
        XCTAssertTrue(movies.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.sources.heading"].waitForExistence(timeout: 15))
        remote.press(.menu)
        XCTAssertTrue(app.buttons["ntv.detail.sources"].waitForExistence(timeout: 15))
        capture("ntv-detail-return-from-sources")
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
        let focusedSeries = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.poster.series.")).firstMatch
        for _ in 0..<4 {
            if focusedSeries.exists { break }
            remote.press(.down)
            if focusedSeries.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(focusedSeries.exists)
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.series.backdrop",
                                      contentID: String(focusedSeries.identifier.dropFirst("ntv.poster.series.".count))))
        capture("ntv-series-focus-backdrop")
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

    private func backdropMatches(_ app: XCUIApplication, identifier: String, contentID: String) -> Bool {
        let backdrop = app.descendants(matching: .any)[identifier].firstMatch
        guard !contentID.isEmpty, backdrop.waitForExistence(timeout: 8) else { return false }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", contentID), object: backdrop
        )], timeout: 8) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
