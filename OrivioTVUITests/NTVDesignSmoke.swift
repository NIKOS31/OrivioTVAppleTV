import XCTest

/// Exercises the actual tvOS remote and the existing navigation callbacks.
/// Navigation remains covered offline. The catalog journey additionally uses
/// the engine's default Cinemeta addon, exercising real generic catalog data.
final class NTVDesignSmoke: XCTestCase {
    func testSeanimeCatalogRapidMovesYieldToNewNavigation() {
        exerciseCatalogRapidMoves(seanime: true)
    }

    func testTopMenuCatalogRapidMovesYieldToNewNavigation() {
        exerciseCatalogRapidMoves(seanime: false)
    }

    private func exerciseCatalogRapidMoves(seanime: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvCatalogCategoriesDemo", "-ntvRowLayoutFixture"]
        if seanime { app.launchArguments.append("-ntvSeanimeDemo") }
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let movies = app.buttons["ntv.navigation.5"]
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(seanime ? .right : .down)
        XCTAssertTrue(focused(first, timeout: 8))
        if seanime {
            remote.press(.up)
            XCTAssertTrue(focused(app.buttons["ntv.catalog.movie.openCategories"], timeout: 8))
            remote.press(.select)
        } else { remote.press(.left) }
        let categoryPrefix = "ntv.category.movie."
        let categories = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", categoryPrefix))
        XCTAssertTrue(categories.firstMatch.waitForExistence(timeout: 8))
        let ids = categories.allElementsBoundByIndex.map(\.identifier)
        XCTAssertGreaterThanOrEqual(ids.count, 2)
        let sourceIDs = ids.prefix(2).map { String($0.dropFirst(categoryPrefix.count)) }
        let rows = sourceIDs.map { app.descendants(matching: .any)["ntv.catalog.shelf." + $0].firstMatch }
        remote.press(.right)
        let rowFirst = rows[0].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(focused(rowFirst, timeout: 8))
        for _ in 0..<6 { remote.press(.right) }
        remote.press(.down)
        let nextPosters = rows[1].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie."))
        let nextFirst = nextPosters.firstMatch
        XCTAssertTrue(focused(nextFirst, timeout: 8), "A vertical entry starts the next shelf at its first poster.")
        remote.press(.right)
        let nextSecond = nextPosters.element(boundBy: 1)
        XCTAssertTrue(focused(nextSecond, timeout: 5))
        // Covers the full existing 360ms retry window after the next action.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(nextSecond.hasFocus, "An old category entry must not pull the viewer back after Right.")
        remote.press(.up)
        remote.press(.down)
        remote.press(.up)
        XCTAssertTrue(focused(rowFirst, timeout: 8), "Alternating rows must finish on the destination of the latest command.")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(rowFirst.hasFocus)
        XCTAssertFalse(app.descendants(matching: .any)["ntv.catalog.movie.categoryPanel"].firstMatch.exists)
        capture(seanime ? "ntv-seanime-catalog-rapid-row-moves" : "ntv-top-catalog-rapid-row-moves")
    }

    func testSeanimeCategoriesAndMainRailHaveDistinctRemotePaths() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvSeanimeDemo", "-ntvCatalogCategoriesDemo", "-ntvRowLayoutFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        let movies = app.buttons["ntv.navigation.5"]
        let remote = XCUIRemote.shared
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.right)
        XCTAssertTrue(focused(first, timeout: 8))
        let trigger = app.buttons["ntv.catalog.movie.openCategories"]
        for _ in 0..<3 {
            remote.press(.up)
            XCTAssertTrue(focused(trigger, timeout: 8), "Up from the first shelf must reach Categories in the left-menu layout.")
            remote.press(.down)
            XCTAssertTrue(focused(first, timeout: 8), "Down from Categories must reach the first poster even if UIKit initially chooses See All.")
        }
        remote.press(.up)
        XCTAssertTrue(focused(trigger, timeout: 8))
        remote.press(.select)
        let panel = app.descendants(matching: .any)["ntv.catalog.movie.categoryPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let category = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.category.movie.")).firstMatch
        XCTAssertTrue(focused(category, timeout: 8))
        capture("ntv-seanime-categories-from-header")
        remote.press(.right)
        XCTAssertTrue(focused(first, timeout: 8))
        XCTAssertFalse(panel.exists)
        remote.press(.left)
        XCTAssertTrue(focused(movies, timeout: 8), "The left boundary belongs to the main rail, without opening a second drawer.")
        XCTAssertFalse(panel.exists)
        capture("ntv-seanime-catalog-main-rail")
    }

    func testSeanimeRailFitsAndKeepsHomeGeometryStableWhenExpanded() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvSeanimeDemo", "-ntvRowLayoutFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let spotlight = app.buttons["ntv.home.spotlight"]
        let home = app.buttons["ntv.navigation.0"]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 20))
        let screen = app.windows.firstMatch.frame
        let heading = app.staticTexts["ntv.home.heading"]
        capture("ntv-seanime-home-cover-and-summary")
        XCTAssertGreaterThan(heading.frame.minX, home.frame.maxX + 8)
        let headingBefore = heading.frame
        let feature = app.descendants(matching: .any)["ntv.seanime.home.feature"].firstMatch
        XCTAssertTrue(feature.exists)
        let canvas = app.descendants(matching: .any)["ntv.canvas"].firstMatch
        XCTAssertTrue(canvas.exists)
        let canvasBefore = canvas.frame
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            if home.hasFocus { break }
            remote.press(.menu)
            if focused(home, timeout: 2) { break }
        }
        XCTAssertTrue(focused(home, timeout: 5))
        for id in [0, 5, 6, 8, 1, 2, 4, 7, 3] {
            let item = app.buttons["ntv.navigation.\(id)"]
            if item.exists { XCTAssertTrue(screen.contains(item.frame), "Every available rail item must fit the screen.") }
        }
        XCTAssertEqual(heading.frame.minX, headingBefore.minX, accuracy: 1)
        // Accessibility reports the feature's opaque text bounds, which vary
        // with metadata and focus. The canvas measures the actual page width.
        XCTAssertEqual(canvas.frame.width, canvasBefore.width, accuracy: 1,
                       "Opening the rail must overlay content rather than squeeze its feature.")
        capture("ntv-seanime-expanded-navigation")
        remote.press(.menu)
        XCTAssertTrue(focused(spotlight, timeout: 8), "Back closes the rail into Home's existing content route.")
        XCTAssertEqual(heading.frame.minX, headingBefore.minX, accuracy: 1)
        capture("ntv-seanime-home-after-menu")
        let firstProposal = spotlight.value as? String
        XCTAssertNotNil(firstProposal)
        remote.press(.right)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", firstProposal ?? ""), object: spotlight)], timeout: 8), .completed,
            "Right on the minimal hero must change the proposal without opening its detail.")
        XCTAssertTrue(focused(spotlight, timeout: 5))
        remote.press(.left)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", firstProposal ?? ""), object: spotlight)], timeout: 8), .completed,
            "Left must return to the previous proposal, without opening the rail.")
        XCTAssertTrue(focused(spotlight, timeout: 5))
        let firstPoster = app.buttons["ntv.home.poster.movie.fixture.row.0.item.0"]
        for _ in 0..<6 {
            if firstPoster.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(firstPoster, timeout: 8), "Manual hero navigation must retain the native Down path to the first row.")
    }

    func testRecentSearchesLeaveSpaceForPostersAndClearBackToTheField() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-searchDemo",
            "-ntvSearchLayoutFixture", "-ntvRecentSearchesFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let field = app.buttons["ntv.search.field"]
        let clear = app.buttons["ntv.search.recent.clear"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        let posters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.search.poster.")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(posters.count, 6)
        let screen = app.windows.firstMatch.frame
        let top = posters.map(\.frame.minY).min() ?? screen.maxY
        XCTAssertGreaterThan(top, clear.frame.maxY, "History and posters must be separate rows.")
        XCTAssertLessThan(top, screen.minY + screen.height * 0.6,
                          "A horizontal history scroller must not consume the result grid's height.")
        capture("ntv-search-recent-with-posters")
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            if field.hasFocus { break }
            remote.press(.down)
            if focused(field, timeout: 2) { break }
        }
        XCTAssertTrue(focused(field, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(clear, timeout: 5), "The clear action must be reachable without opening the keyboard.")
        remote.press(.select)
        XCTAssertTrue(focused(field, timeout: 5), "Removing the focused history must return to Search.")
        XCTAssertFalse(clear.exists)
        XCTAssertFalse(app.textFields["ntv.search.editor"].exists)
        capture("ntv-search-history-cleared-focus-restored")
    }

    func testAdvancedSubtitleOptionsStayNearTransportAndRestoreFocus() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        var opened = false
        for _ in 0..<10 {
            remote.press(.up)
            if play.waitForExistence(timeout: 2) { opened = true; break }
        }
        XCTAssertTrue(opened, "The native fixture must expose its transport before pausing.")
        // Pause the fresh autoplay fixture before the slower accessibility queries.
        // Otherwise its five-second idle timer can remove Play between snapshots.
        remote.press(.playPause)
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        remote.press(.down)
        XCTAssertTrue(focused(app.buttons["ntv.player.info"], timeout: 5))
        for _ in 0..<3 { remote.press(.right) }
        let subtitles = app.buttons["ntv.player.subtitles"]
        XCTAssertTrue(focused(subtitles, timeout: 5))
        remote.press(.select)
        let settings = app.buttons["ntv.player.tracks.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let trackPicker = app.descendants(matching: .any)["ntv.player.trackPicker"].firstMatch
        let playerScreen = app.windows.firstMatch.frame
        XCTAssertTrue(playerScreen.contains(trackPicker.frame))
        XCTAssertLessThan(trackPicker.frame.width, playerScreen.width / 3,
                          "Track selection must stay compact beside the transport.")
        XCTAssertLessThan(trackPicker.frame.height, playerScreen.height / 2)
        for _ in 0..<8 {
            if settings.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(settings, timeout: 5))
        remote.press(.select)
        let tab = app.buttons["ntv.player.settings.tab.3"]
        XCTAssertTrue(focused(tab, timeout: 8))
        let card = app.descendants(matching: .any)["ntv.player.settings.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(card.frame))
        XCTAssertLessThanOrEqual(card.frame.height, 380, "Advanced options must scroll inside a bounded card.")
        XCTAssertGreaterThan(card.frame.midY, screen.midY, "Advanced subtitle settings must be anchored in the lower half.")
        capture("ntv-player-subtitle-advanced-settings-bottom")
        remote.press(.down)
        let font = app.buttons["ntv.player.settings.row.sub.font"]
        if !font.hasFocus { remote.press(.right) }
        if !font.hasFocus { remote.press(.down) }
        XCTAssertTrue(focused(font, timeout: 5), "Font must be reachable from the subtitle track and option columns.")
        remote.press(.select)
        let picker = app.descendants(matching: .any)["ntv.player.picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let gap = screen.maxY - picker.frame.maxY
        capture("ntv-player-subtitle-font-picker-bottom")
        XCTAssertTrue(screen.contains(picker.frame))
        XCTAssertLessThan(picker.frame.width, screen.width / 3)
        XCTAssertLessThan(picker.frame.height, screen.height / 2)
        XCTAssertGreaterThanOrEqual(gap, 96, "A nested option must inherit the transport anchor, not open as a full-screen picker.")
        XCTAssertLessThanOrEqual(gap, 180)
        remote.press(.menu)
        XCTAssertTrue(focused(font, timeout: 8), "Back from a nested choice must restore its settings row.")
    }

    func testSearchFocusKeepsGlassAndOpensNativeInputOnSelection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-searchDemo", "-ntvSearchLayoutFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let field = app.buttons["ntv.search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        let posters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.search.poster.")).allElementsBoundByIndex
        XCTAssertFalse(posters.isEmpty)
        let screen = app.windows.firstMatch.frame
        let top = posters.map(\.frame.minY).min() ?? 0
        let firstRow = posters.filter { abs($0.frame.minY - top) < 30 }
        XCTAssertLessThanOrEqual(firstRow.map(\.frame.minX).min() ?? screen.maxX, screen.minX + 60)
        XCTAssertGreaterThanOrEqual(firstRow.map(\.frame.maxX).max() ?? 0, screen.maxX - 60,
                                    "Search must use both sides of the available viewport.")
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            if field.hasFocus { break }
            remote.press(.down)
            if focused(field, timeout: 2) { break }
        }
        XCTAssertTrue(focused(field, timeout: 8))
        XCTAssertFalse(app.textFields["ntv.search.editor"].exists, "Focusing Search alone must not mount the native editing surface.")
        capture("ntv-search-glass-focused")
        remote.press(.select)
        let editor = app.textFields["ntv.search.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Selection must retain the native keyboard and dictation entry.")
        capture("ntv-search-native-input")
        for _ in 0..<3 {
            if !editor.exists { break }
            remote.press(.menu)
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(focused(field, timeout: 8), "Dismissal must restore the glass field, not strand focus in the keyboard.")
    }

    func testPlayerQuickSkipStaysDiscreetAndVisibleControlsDwell() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        for _ in 0..<10 {
            remote.press(.up)
            if play.waitForExistence(timeout: 2) { break }
        }
        // Stabilize startup snapshots paused, then exercise the live skip and dwell.
        remote.press(.playPause)
        XCTAssertTrue(play.exists)
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        remote.press(.playPause)
        remote.press(.right)
        Thread.sleep(forTimeInterval: 1.2)
        // Read presence and playback atomically; a second live query can outlast the idle dwell.
        let runningControl = try play.snapshot()
        XCTAssertEqual(runningControl.identifier, "ntv.player.play", "Already-open controls must survive the seek commit and remain visible for their dwell.")
        XCTAssertEqual(runningControl.label, "Pause", "The quick skip and its dwell must run during playback.")
        // Screenshot capture can exceed the idle dwell; freeze only this evidence step.
        remote.press(.playPause)
        XCTAssertEqual(play.label, "Lecture")
        capture("ntv-player-quick-skip-visible-controls")
        remote.press(.menu)
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(play.exists)
        remote.press(.playPause)
        remote.press(.right)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertFalse(app.staticTexts["ntv.player.position"].firstMatch.exists,
                       "A skip over bare video must not flash a timeline that disappears at commit.")
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertFalse(play.exists)
        capture("ntv-player-discreet-quick-skip")
        remote.press(.up)
        XCTAssertTrue(play.waitForExistence(timeout: 8), "Explicit Up must still open all transport controls after the skip.")
        remote.press(.playPause)
        XCTAssertEqual(play.label, "Lecture", "The bare-video skip must also preserve playback.")
    }

    func testPlaybackOptionsOpenNearTransportAndKeepSubtitleTabReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        for _ in 0..<10 {
            remote.press(.up)
            if play.waitForExistence(timeout: 2) { break }
        }
        // Pause before snapshotting so the five-second idle timer cannot close the controls.
        remote.press(.playPause)
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        remote.press(.down)
        let info = app.buttons["ntv.player.info"]
        XCTAssertTrue(focused(info, timeout: 8))
        remote.press(.select)
        let first = app.buttons["ntv.player.settings.tab.0"]
        XCTAssertTrue(focused(first, timeout: 8))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(first.frame.minY, screen.minY + screen.height * 0.35,
                             "The options must open in the transport area, not at the upper edge of the film.")
        capture("ntv-player-bottom-options")
        for _ in 0..<3 { remote.press(.right) }
        let subtitles = app.buttons["ntv.player.settings.tab.3"]
        XCTAssertTrue(focused(subtitles, timeout: 8))
        XCTAssertGreaterThan(subtitles.frame.minY, screen.minY + screen.height * 0.35)
        capture("ntv-player-bottom-subtitle-settings")
        remote.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 8) || !first.exists,
                      "Back must close the settings and hand focus back to the normal player.")
    }

    func testRepeatedHomeRowMovesKeepFocusVisibleAndViewportStable() {
        exerciseRepeatedHomeRows(seanime: false)
    }

    func testSeanimeRepeatedHomeRowMovesKeepFocusVisibleAndViewportStable() {
        exerciseRepeatedHomeRows(seanime: true)
    }

    private func exerciseRepeatedHomeRows(seanime: Bool) {
        continueAfterFailure = false
        executionTimeAllowance = 300
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvRowLayoutFixture"]
        if seanime { app.launchArguments.append("-ntvSeanimeDemo") }
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let settings = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        remote.press(.menu)
        XCTAssertTrue(focused(settings, timeout: 8))
        for _ in 0..<9 {
            if app.buttons["ntv.navigation.0"].hasFocus { break }
            remote.press(seanime ? .up : .left)
        }
        XCTAssertTrue(focused(app.buttons["ntv.navigation.0"], timeout: 5))
        remote.press(.select)
        if seanime { remote.press(.right) }
        let spotlight = app.buttons["ntv.home.spotlight"]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 15))
        let feature = app.descendants(matching: .any)["ntv.seanime.home.feature"].firstMatch
        XCTAssertEqual(feature.buttons.count, 1, "The minimal feature has one detail action, without arrow or pause targets.")
        // The editorial action is offset from poster zero. Enter the first
        // shelf before aligning its first column through real remote moves.
        let firstShelfFocus = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true",
            "ntv.home.poster.movie.fixture.row.0.item.")).firstMatch
        for _ in 0..<6 {
            if firstShelfFocus.exists { break }
            remote.press(.down)
        }
        XCTAssertTrue(firstShelfFocus.exists)
        let first = app.buttons["ntv.home.poster.movie.fixture.row.0.item.0"]
        for _ in 0..<24 {
            if first.hasFocus { break }
            remote.press(.left)
        }
        XCTAssertTrue(focused(first, timeout: 8))
        let navigation = app.buttons["ntv.navigation.0"]
        for row in 1...4 {
            // The device recording starts its vertical moves from a column
            // well beyond poster zero. First-column-only checks missed this.
            for _ in 0..<9 { remote.press(.right) }
            let departing = app.buttons["ntv.home.poster.movie.fixture.row.\(row - 1).item.9"]
            XCTAssertTrue(focused(departing, timeout: 8))
            remote.press(.down)
            let destination = app.buttons["ntv.home.poster.movie.fixture.row.\(row).item.0"]
            XCTAssertTrue(focused(destination, timeout: 8))
            Thread.sleep(forTimeInterval: 0.35)
            let settled = destination.frame
            XCTAssertGreaterThan(settled.minY, seanime ? app.windows.firstMatch.frame.minY + 8 : navigation.frame.maxY + 8)
            XCTAssertLessThan(settled.maxY, app.windows.firstMatch.frame.maxY - 8)
            Thread.sleep(forTimeInterval: 0.8)
            XCTAssertTrue(destination.hasFocus, "No delayed retry may pull focus to a different row.")
            XCTAssertFalse(navigation.hasFocus, "Up/Down inside Home must never expand the side rail or jump to the hero.")
            XCTAssertEqual(destination.frame.minY, settled.minY, accuracy: 2,
                           "Settled focus must not cause a second vertical adjustment.")
            remote.press(.right)
            XCTAssertTrue(focused(app.buttons["ntv.home.poster.movie.fixture.row.\(row).item.1"], timeout: 8))
            Thread.sleep(forTimeInterval: 0.45)
            XCTAssertTrue(app.buttons["ntv.home.poster.movie.fixture.row.\(row).item.1"].hasFocus,
                          "A new remote command must cancel the first-poster landing.")
            remote.press(.left)
            XCTAssertTrue(focused(destination, timeout: 8))
            remote.press(.up)
            XCTAssertTrue(focused(app.buttons["ntv.home.poster.movie.fixture.row.\(row - 1).item.0"], timeout: 8))
            remote.press(.down)
            XCTAssertTrue(focused(destination, timeout: 8))
        }
        capture(seanime ? "ntv-seanime-home-repeated-row-navigation" : "ntv-home-repeated-row-navigation")
    }

    func testSystemPrimaryIconRefreshIsPerformedOnceForLegacyInstalls() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        let remote = XCUIRemote.shared
        let system = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        defer { app.terminate() }
        let baseArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvIconRegistrationProbe"]
        let probe = app.descendants(matching: .any)["ntv.systemIcon.registration"].firstMatch
        func waitForPrimary(notificationsBeforeSnapshot: Int? = nil) -> String {
            // Expected system dialogs must be handled before querying the covered app.
            for _ in 0..<(notificationsBeforeSnapshot ?? 2) {
                let confirmation = system.buttons["OK"]
                guard confirmation.waitForExistence(timeout: notificationsBeforeSnapshot == nil ? 2 : 15) else {
                    if notificationsBeforeSnapshot != nil {
                        capture("ntv-icon-confirmation-missing")
                        XCTFail("Each icon request must present its genuine system confirmation.")
                        return "missing-confirmation"
                    }
                    break
                }
                XCTAssertTrue(system.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "icon for")).firstMatch.exists)
                remote.press(.select)
                // The next identical dialog can arrive only after dismissal finishes.
                Thread.sleep(forTimeInterval: 2)
            }
            guard probe.waitForExistence(timeout: 15) else { return "missing" }
            let deadline = Date().addingTimeInterval(35)
            while Date() < deadline {
                let value = probe.value as? String ?? ""
                if value.hasPrefix("applied#primary#") || value.hasPrefix("failed#") ||
                    value.hasPrefix("unavailable#") || value.hasPrefix("mismatch#") { return value }
                Thread.sleep(forTimeInterval: 0.2)
            }
            return probe.value as? String ?? "timed-out"
        }
        // Establish a real primary state without assuming test ordering.
        app.launchArguments = baseArguments
        app.launch()
        XCTAssertTrue(waitForPrimary().hasPrefix("applied#primary#"))
        app.terminate()
        app.launchArguments = baseArguments + ["-ntvPrimaryIconRefreshFixture"]
        app.launch()
        XCTAssertEqual(waitForPrimary(notificationsBeforeSnapshot: 2), "applied#primary#2",
                       "A legacy install already reporting primary must actually select the alternate and restore the primary.")
        remote.press(.home)
        remote.press(.home)
        Thread.sleep(forTimeInterval: 1)
        let switcher = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        switcher.name = "ntv-system-primary-refresh-app-switcher"
        switcher.lifetime = .keepAlways
        add(switcher)
        remote.press(.menu)
        app.terminate()
        app.launchArguments = baseArguments
        app.launch()
        XCTAssertEqual(waitForPrimary(notificationsBeforeSnapshot: 0), "applied#primary#0",
                       "A completed refresh must not repeat notifications at the next launch.")
    }

    func testSystemIconRegistrationAndActualSwitcherCapture() {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvIconRegistrationProbe", "-ntvLegacyIconFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        let remote = XCUIRemote.shared
        let iconNotificationMonitor = addUIInterruptionMonitor(withDescription: "Acknowledge the genuine icon-change notification") { alert in
            let iconMessage = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "icon for")).firstMatch
            guard iconMessage.exists, alert.buttons["OK"].exists else { return false }
            remote.press(.select)
            return true
        }
        defer { removeUIInterruptionMonitor(iconNotificationMonitor) }
        app.launch()
        defer { app.terminate() }
        // The genuine icon confirmation prevents snapshots of app elements.
        // UIKit presents it after launch has already returned (observed at
        // 3.94s after a 3.62s launch). Let its presentation settle before the
        // remote click; querying the app while it is covered can time out.
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "ntv-system-icon-registration"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        remote.press(.select)
        let probe = app.descendants(matching: .any)["ntv.systemIcon.registration"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(25)
        var confirmations = 0
        while Date() < deadline {
            let value = probe.value as? String ?? ""
            if value.hasPrefix("applied#NTVSystemIcon#") { break }
            if value.hasPrefix("failed#") || value.hasPrefix("unavailable#") || value.hasPrefix("mismatch#") { break }
            if value.hasPrefix("applying#"), confirmations < 3 {
                // The genuine Apple icon request can present a system dialog.
                // This remote journey can acknowledge it; a unit test cannot.
                Thread.sleep(forTimeInterval: 1)
                remote.press(.select)
                confirmations += 1
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue((probe.value as? String ?? "").hasPrefix("applied#NTVSystemIcon#"),
                      "The seed must observe the actual selected alternate, whether previously present or set by UIKit now.")
        // A fresh install alone hid the physical switcher regression. Start
        // with the previous selected alternate, then relaunch with migration.
        app.terminate()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvIconRegistrationProbe"]
        app.launch()
        Thread.sleep(forTimeInterval: 1)
        let primary = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        primary.name = "ntv-system-primary-icon-migration"
        primary.lifetime = .keepAlways
        add(primary)
        remote.press(.select)
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        let primaryDeadline = Date().addingTimeInterval(25)
        var primaryConfirmations = 0
        while Date() < primaryDeadline {
            let value = probe.value as? String ?? ""
            if value == "applied#primary#1" { break }
            if value.hasPrefix("failed#") || value.hasPrefix("unavailable#") || value.hasPrefix("mismatch#") { break }
            if value.hasPrefix("applying#"), primaryConfirmations < 3 {
                Thread.sleep(forTimeInterval: 1)
                remote.press(.select)
                primaryConfirmations += 1
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(probe.value as? String, "applied#primary#1",
                       "Restoring the verified primary n must perform one real public UIKit request after the previous alternate state.")
        remote.press(.home)
        remote.press(.home)
        Thread.sleep(forTimeInterval: 1)
        let switcher = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        switcher.name = "ntv-system-app-switcher"
        switcher.lifetime = .keepAlways
        add(switcher)
        remote.press(.menu)
    }

    func testEntirelyFilteredCatalogKeepsCategoriesAndTopMenuReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvCatalogCategoriesDemo", "-ntvUpcomingCatalogFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let movies = app.buttons["ntv.navigation.5"]
        let recovery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.catalog.filteredEmpty.")).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).count, 0)
        let remote = XCUIRemote.shared
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 8))
        remote.press(.down)
        let focusedRecovery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.catalog.filteredEmpty.")).firstMatch
        XCTAssertTrue(focusedRecovery.waitForExistence(timeout: 8), "All-hidden filters must not leave focus trapped in the top menu.")
        // A hashed catalog identity can exceed XCTest's 128-character
        // string-subscript limit. Explicit predicates accept the full ID.
        let selectedRecovery = app.buttons.matching(NSPredicate(format: "identifier == %@", focusedRecovery.identifier)).firstMatch
        capture("ntv-catalog-all-filtered-empty")
        remote.press(.select)
        let panel = app.descendants(matching: .any)["ntv.catalog.movie.categoryPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        remote.press(.right)
        XCTAssertTrue(focused(selectedRecovery, timeout: 8), "A filtered category must retain its recovery control after closing the drawer.")
        XCTAssertFalse(panel.exists)
        remote.press(.menu)
        XCTAssertTrue(focused(movies, timeout: 8))
    }

    func testHomeDoesNotUseOtherAddonsWithoutXperience() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["ntv.home.heading"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["ntv.home.empty"].firstMatch.waitForExistence(timeout: 20))
        // Continue Watching may legitimately seed a spotlight after another
        // journey. Catalog exclusion concerns addon rows, not local progress.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.home.poster.")).count, 0)
        capture("ntv-home-without-xperience")
        app.terminate()
    }

    func testCatalogCategoryPanelReturnsToItsPosterRow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvCatalogCategoriesDemo", "-ntvHalloweenDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        let panel = app.descendants(matching: .any)["ntv.catalog.movie.categoryPanel"].firstMatch
        let firstMovie = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 60))
        XCTAssertFalse(panel.exists, "The side menu must stay hidden while browsing.")
        let remote = XCUIRemote.shared
        // Enter the gallery, then open the drawer only at its left edge.
        let topMovies = app.buttons["ntv.navigation.5"]
        for _ in 0..<3 {
            if topMovies.hasFocus { break }
            remote.press(.menu)
            if focused(topMovies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(topMovies, timeout: 8))
        remote.press(.down)
        XCTAssertTrue(focused(firstMovie, timeout: 8), "Down from the top menu must reach the first poster.")
        XCTAssertFalse(panel.exists, "Down must not open the category drawer.")
        let openingPosterFrame = settledFrame(firstMovie)
        let canvas = app.descendants(matching: .any)["ntv.canvas"].firstMatch
        let openingCanvasFrame = canvas.frame
        remote.press(.right)
        remote.press(.left)
        XCTAssertTrue(focused(firstMovie, timeout: 8))
        XCTAssertFalse(panel.exists, "Returning to the first poster does not open the menu until another Left.")
        remote.press(.left)
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.category.movie.")).firstMatch
        XCTAssertTrue(focused(first, timeout: 8))
        let categoryIDs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.category.movie.")).allElementsBoundByIndex.map(\.identifier)
        XCTAssertGreaterThanOrEqual(categoryIDs.count, 2, "The row-change regression needs two distinct catalogs.")
        let firstCategoryID = first.identifier
        capture("ntv-catalog-categories")
        XCTAssertEqual(canvas.frame, openingCanvasFrame, "Opening the drawer must not resize the artwork.")
        remote.press(.select)
        let poster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 60), "Selecting a category must land on a loaded poster row.")
        XCTAssertFalse(panel.exists, "Selecting a category must close its drawer.")
        XCTAssertEqual(canvas.frame, openingCanvasFrame)
        XCTAssertEqual(settledFrame(firstMovie).minX, openingPosterFrame.minX, accuracy: 2, "Closing the drawer must restore the same poster position.")
        capture("ntv-catalog-category-selected")
        let prefix = "ntv.category.movie."
        let firstRow = app.descendants(matching: .any)["ntv.catalog.shelf." + String(firstCategoryID.dropFirst(prefix.count))].firstMatch
        let firstPoster = firstRow.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(focused(firstPoster, timeout: 8))
        // Start away from the first column, exactly as the physical report.
        for _ in 0..<10 { remote.press(.right) }
        XCTAssertFalse(firstPoster.exists && firstPoster.hasFocus)
        XCTAssertFalse(panel.exists, "A long horizontal browse must not open the side menu.")
        remote.press(.down)
        let nextRow = app.descendants(matching: .any)["ntv.catalog.shelf." + String(categoryIDs[1].dropFirst(prefix.count))].firstMatch
        let nextFirst = nextRow.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.poster.movie.")).firstMatch
        XCTAssertTrue(focused(nextFirst, timeout: 15), "Down from a later column must select the FIRST poster of the next row.")
        capture("ntv-catalog-down-first-poster")
        remote.press(.up)
        remote.press(.down)
        remote.press(.up)
        XCTAssertTrue(focused(firstPoster, timeout: 8))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(firstPoster.hasFocus, "A stale row-transfer retry must not pull focus back after fast Up/Down/Up moves.")
        remote.press(.down)
        XCTAssertTrue(focused(nextFirst, timeout: 8))
        remote.press(.up)
        XCTAssertTrue(focused(firstPoster, timeout: 8), "Up must return to the first poster, without a far-end landing.")
        remote.press(.left)
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertTrue(focused(first, timeout: 8), "Left from the first poster must reach its visible category.")
        remote.press(.up)
        let header = app.buttons["ntv.catalog.movie.categories"]
        XCTAssertTrue(focused(header, timeout: 8), "The Categories button must be reachable with the remote.")
        capture("ntv-catalog-categories-header-focused")
        remote.press(.select)
        XCTAssertTrue(focused(first, timeout: 8))
        remote.press(.right)
        XCTAssertTrue(focused(firstPoster, timeout: 8), "Right from categories must land on a poster, without bouncing back to the top bar.")
        XCTAssertFalse(panel.exists)
        remote.press(.left)
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertTrue(focused(first, timeout: 8))
        remote.press(.menu)
        XCTAssertTrue(focused(firstPoster, timeout: 8), "Back must close the drawer and return to its row.")
        XCTAssertFalse(panel.exists)
        remote.press(.menu)
        let movies = app.buttons["ntv.navigation.5"]
        XCTAssertTrue(focused(movies, timeout: 8), "Back from categories must still reach the top menu.")
        let moviesFrame = movies.frame
        let series = app.buttons["ntv.navigation.6"]
        let seriesCenter = series.frame.midX
        remote.press(.right)
        XCTAssertTrue(focused(series, timeout: 8))
        // tvOS reports only a label's opaque content when it has no focus
        // fill. Compare stable centres and the two FOCUSED hit areas instead.
        XCTAssertEqual(movies.frame.midX, moviesFrame.midX, accuracy: 2, "Leaving a tab must not move its label.")
        XCTAssertEqual(series.frame.midX, seriesCenter, accuracy: 2, "Entering a tab must not move its label.")
        XCTAssertEqual(series.frame.width, moviesFrame.width, accuracy: 2, "Adjacent focused tabs must retain equal allocated widths.")
        XCTAssertEqual(series.frame.height, moviesFrame.height, accuracy: 2)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.catalog.series.heading"].waitForExistence(timeout: 20))
        let seriesPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.poster.series.")).firstMatch
        for _ in 0..<4 {
            if seriesPoster.exists { break }
            remote.press(.down)
            if seriesPoster.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(seriesPoster.exists)
        let selectedSeriesID = seriesPoster.identifier
        let seriesPanel = app.descendants(matching: .any)["ntv.catalog.series.categoryPanel"].firstMatch
        XCTAssertFalse(seriesPanel.exists)
        remote.press(.left)
        XCTAssertTrue(seriesPanel.waitForExistence(timeout: 8))
        let seriesCategory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.category.series.")).firstMatch
        XCTAssertTrue(focused(seriesCategory, timeout: 8))
        capture("ntv-series-categories-reachable")
        remote.press(.right)
        XCTAssertTrue(seriesPoster.waitForExistence(timeout: 60), "The same side menu hand-off must work on Séries.")
        XCTAssertEqual(seriesPoster.identifier, selectedSeriesID)
        XCTAssertFalse(seriesPanel.exists)
        app.terminate()
    }
    func testLiveTabSeparatesTelevisionAndTwitchWithoutATVAddon() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo", "-liveTVDemo", "-ntvTwitchDemo"]
        app.launch()
        let remote = XCUIRemote.shared
        let heading = app.staticTexts["ntv.live.hub.heading"]
        let television = app.buttons["ntv.live.section.television"]
        let twitch = app.buttons["ntv.live.section.twitch"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        XCTAssertTrue(focused(television, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(twitch.frame))
        capture("ntv-live-hub-television")
        remote.press(.right)
        XCTAssertTrue(focused(twitch, timeout: 5))
        remote.press(.select)
        let connect = app.buttons["ntv.twitch.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "Twitch is reachable even with no TV channels configured.")
        XCTAssertTrue(focused(connect, timeout: 5))
        XCTAssertTrue(heading.exists, "The Twitch browser remains inside the Live TV page.")
        XCTAssertFalse(app.buttons["ntv.twitch.close"].exists, "The embedded browser uses the common section navigation.")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.twitch.code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ntv.twitch.followed"].waitForExistence(timeout: 20))
        let followed = app.buttons["ntv.twitch.followed"]
        XCTAssertTrue(focused(followed, timeout: 5))
        let stream = app.buttons["ntv.twitch.stream.fixture-live"]
        XCTAssertTrue(stream.waitForExistence(timeout: 10))
        capture("ntv-live-hub-twitch")
        for _ in 0..<5 {
            if stream.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(stream, timeout: 5))
        remote.press(.select)
        // Freeze AVKit before snapshot queries, as in the standalone Twitch journey.
        Thread.sleep(forTimeInterval: 2)
        remote.press(.playPause)
        let video = app.descendants(matching: .any)["ntv.twitch.player.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        // The native AVPlayer controls can consume Back to hide their HUD first.
        // Keep the same bounded return gesture as the standalone player test.
        for _ in 0..<3 {
            remote.press(.menu)
            if followed.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(followed.waitForExistence(timeout: 5))
        XCTAssertFalse(video.exists)
        XCTAssertTrue(heading.exists, "Back from the player preserves the embedded Twitch browser.")
        remote.press(.menu)
        XCTAssertTrue(focused(television, timeout: 5), "Back from Twitch returns to the television selector.")
        XCTAssertTrue(heading.exists)
        XCTAssertFalse(app.buttons["ntv.twitch.followed"].exists)
        remote.press(.right)
        let reopenFocused = focused(twitch, timeout: 5)
        let reopenDescription = app.debugDescription
        capture("ntv-live-hub-reentry")
        remote.press(.select)
        let reopened = followed.waitForExistence(timeout: 20)
        XCTAssertTrue(reopenFocused, "The viewer can reopen Twitch from the common section bar. Opened: \(reopened)\n" + reopenDescription)
        XCTAssertTrue(reopened, "Reopening Twitch restores its saved connection.")
        XCTAssertTrue(focused(followed, timeout: 5))
        app.terminate()
    }

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
        for _ in 0..<5 {
            if stream.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(stream, timeout: 5), "A followed channel must be selectable with the remote.")
        remote.press(.select)
        // Pause AVKit before querying its continuously updating accessibility tree.
        Thread.sleep(forTimeInterval: 2)
        remote.press(.playPause)
        let video = app.descendants(matching: .any)["ntv.twitch.player.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20), "Selecting a channel opens the native player inside nTV.")
        XCTAssertFalse(app.staticTexts["ntv.twitch.player.error"].exists)
        capture("ntv-twitch-native-player")
        // AVKit exposes transport-bar custom menus as collection cells,
        // including their accessibility label and remote focus behaviour.
        let quality = app.cells["Qualité"].firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 5),
                      "The native transport bar must expose the quality menu.\n" + app.debugDescription)
        capture("ntv-twitch-quality-control")
        remote.press(.playPause)
        for _ in 0..<3 {
            remote.press(.menu)
            if app.buttons["ntv.twitch.followed"].waitForExistence(timeout: 3) { break }
        }
        XCTAssertFalse(video.exists, "Back closes the native player and returns to the Twitch browser.")
        XCTAssertTrue(focused(stream, timeout: 5), "Closing playback must restore the selected live.")
        // The wider 16:9 card is centred below Search. Follow the spatial
        // navigation used by tvOS instead of assuming Up targets Followed.
        let search = app.buttons["ntv.twitch.search"]
        remote.press(.up)
        XCTAssertTrue(focused(search, timeout: 5), "Up from the first live reaches the nearest browser action.")
        let followed = app.buttons["ntv.twitch.followed"]
        remote.press(.left)
        XCTAssertTrue(focused(followed, timeout: 5))
        remote.press(.right)
        XCTAssertTrue(focused(search, timeout: 5))
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

    func testAnimeSeasonCalendarDetailsAndAddonSearchWithRemote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo", "-ntvAnimeFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let settings = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        for _ in 0..<3 {
            if settings.hasFocus { break }
            remote.press(.menu)
            if focused(settings, timeout: 2) { break }
        }
        XCTAssertTrue(focused(settings, timeout: 5))
        let animeTab = app.buttons["ntv.navigation.8"]
        for _ in 0..<8 {
            if animeTab.hasFocus { break }
            remote.press(.left)
        }
        XCTAssertTrue(focused(animeTab, timeout: 5))
        remote.press(.select)
        let season = app.buttons["ntv.anime.season"]
        let planning = app.buttons["ntv.anime.planning"]
        let featured = app.buttons["ntv.anime.featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 20))
        XCTAssertTrue(focused(season, timeout: 8), "The new page must seed a reachable section selector.")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(featured.frame))
        XCTAssertGreaterThan(featured.frame.minY, app.buttons["ntv.navigation.8"].frame.maxY + 8)
        XCTAssertTrue(app.buttons["ntv.anime.seasonPicker"].exists)
        XCTAssertTrue(app.buttons["ntv.anime.yearPicker"].exists)
        XCTAssertTrue(screen.contains(app.buttons["ntv.anime.currentSeason"].frame))
        capture("ntv-anime-season")
        remote.press(.right)
        XCTAssertTrue(focused(planning, timeout: 5))
        remote.press(.select)
        let dayButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.anime.day."))
        XCTAssertEqual(dayButtons.count, 7, "The calendar must display a complete local week.")
        for id in ["previousWeek", "currentWeek", "nextWeek", "followingOnly"] {
            let control = app.buttons["ntv.anime.\(id)"]
            XCTAssertTrue(control.exists)
            XCTAssertTrue(screen.contains(control.frame), "Calendar controls must fit inside the screen.")
        }
        let card = app.buttons["ntv.anime.card.airing.195516"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(screen.contains(card.frame))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "La diffusion ne garantit pas")).firstMatch.exists)
        capture("ntv-anime-planning")
        let focusedDay = dayButtons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<3 {
            if focusedDay.exists { break }
            remote.press(.down)
            if focusedDay.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(focusedDay.waitForExistence(timeout: 5))
        remote.press(.select)
        XCTAssertTrue(focusedDay.value as? String == "Sélectionné")
        let focusedCard = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true", "ntv.anime.card.airing.")).firstMatch
        for _ in 0..<3 {
            if focusedCard.exists { break }
            remote.press(.down)
            if focusedCard.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(focusedCard.waitForExistence(timeout: 5))
        let selectedCard = app.buttons[focusedCard.identifier]
        let selectedTitle = focusedCard.label.components(separatedBy: ", épisode ").first ?? ""
        XCTAssertFalse(selectedTitle.isEmpty)
        remote.press(.select)
        let search = app.buttons["ntv.anime.searchSources"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(focused(search, timeout: 5))
        XCTAssertTrue(screen.contains(search.frame))
        capture("ntv-anime-detail")
        let follow = app.buttons["ntv.anime.follow"]
        let wasFollowed = follow.label.contains("Ne plus suivre")
        for _ in 0..<3 {
            if follow.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(follow, timeout: 5), "Following must be reachable from the detail search action.")
        if !wasFollowed { remote.press(.select) }
        XCTAssertTrue(follow.label.contains("Ne plus suivre"))
        remote.press(.menu)
        XCTAssertTrue(focused(selectedCard, timeout: 8), "Closing an anime must return to its selected calendar card.")
        remote.press(.select)
        XCTAssertTrue(focused(search, timeout: 8))
        remote.press(.select)
        let searchField = app.buttons["ntv.search.field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "The title must route to existing addon search after dismissal.")
        XCTAssertEqual(searchField.value as? String, selectedTitle, "The selected anime title must be retained as the search query.")
        XCTAssertTrue(app.staticTexts["ntv.anime.sources.heading"].exists, "Anime source search must remain inside its own space.")
        capture("ntv-anime-addon-search")
        remote.press(.menu)
        XCTAssertTrue(season.waitForExistence(timeout: 10))
        let animeLibrary = app.buttons["ntv.anime.library"]
        for _ in 0..<5 {
            if animeLibrary.hasFocus { break }
            remote.press(.right)
        }
        XCTAssertTrue(focused(animeLibrary, timeout: 5))
        remote.press(.select)
        let followedCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
            "ntv.anime.followed.", selectedTitle)).firstMatch
        XCTAssertTrue(followedCard.waitForExistence(timeout: 8))
        capture("ntv-anime-library-followed")
        for _ in 0..<6 {
            if followedCard.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(focused(followedCard, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(focused(search, timeout: 8))
        if !wasFollowed {
            for _ in 0..<3 {
                if follow.hasFocus { break }
                remote.press(.down)
            }
            XCTAssertTrue(focused(follow, timeout: 5))
            remote.press(.select)
            XCTAssertTrue(follow.label.contains("Suivre cet animé"), "Restore the fixture’s original follow state.")
        }
        remote.press(.menu)
    }

    func testTopMenuRemoteRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ntvTopMenuDemo", "-ntvHalloweenDemo", "-ntvXperienceHomeFixture", "-ntvNewEpisodeFixture"]
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
        for id in [0, 1, 2, 3, 4, 5, 6, 7, 8] {
            let button = app.buttons["ntv.navigation.\(id)"]
            XCTAssertTrue(screen.contains(button.frame), "Top tab \(id) must stay within the TV screen.")
        }
        for _ in 0..<4 { remote.press(.left) }
        let home = app.buttons["ntv.navigation.0"]
        XCTAssertTrue(focused(home, timeout: 5))
        remote.press(.select)
        let heading = app.staticTexts["ntv.home.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["ntv.home.spotlight"].waitForExistence(timeout: 80))
        XCTAssertGreaterThan(heading.frame.minY, home.frame.maxY + 8,
                             "Home must reserve a visible band below the floating top menu.")
        XCTAssertTrue(screen.contains(heading.frame))
        let newEpisode = app.staticTexts["Nouvel épisode"].firstMatch
        XCTAssertTrue(newEpisode.waitForExistence(timeout: 5))
        XCTAssertTrue(screen.contains(newEpisode.frame), "The explicit new-episode badge must fit within Continue Watching.")
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
        XCTAssertFalse(app.descendants(matching: .any)["ntv.catalog.movie.categoryPanel"].firstMatch.exists)
        XCTAssertLessThanOrEqual(firstMovie.frame.minX, screen.minX + 70, "The closed drawer must leave the full gallery width available.")
        XCTAssertGreaterThanOrEqual(row.map { $0.frame.maxX }.max() ?? 0, screen.maxX - 80,
                                    "The last column must reach the right content margin.")
        capture("ntv-films-full-width")
        app.terminate()
    }

    func testPlayerTimelineCancelAndCommit() {
        continueAfterFailure = false
        func seconds(_ value: String) -> Int {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            XCTAssertTrue(parts.count == 2 || parts.count == 3, "The timeline must expose a readable time.")
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        let app = XCUIApplication()
        app.launchArguments = ["-ntvPlayerDemo"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        let remote = XCUIRemote.shared
        let play = app.buttons["ntv.player.play"]
        // A fresh video starts without chrome. Open it as a viewer does;
        // early Up presses are ignored while the local fixture is loading.
        var opened = false
        for _ in 0..<10 {
            remote.press(.up)
            if play.waitForExistence(timeout: 2) { opened = true; break }
        }
        if !opened { capture("ntv-player-startup-failure") }
        XCTAssertTrue(opened, "The local video fixture must open nTV controls.")
        // Keep the fixture paused while inspecting transport state. Live quick
        // skips and their idle dwell have a separate, unpaused remote journey.
        remote.press(.playPause)
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        let quickPosition = app.staticTexts["ntv.player.position"].firstMatch
        XCTAssertTrue(quickPosition.waitForExistence(timeout: 5))
        let beforeQuickSeek = quickPosition.label
        remote.press(.right)
        XCTAssertNotEqual(quickPosition.label, beforeQuickSeek, "Right from the compact play control must perform a quick skip.")
        XCTAssertTrue(focused(play, timeout: 8))
        XCTAssertEqual(play.label, "Lecture")
        remote.press(.up)
        let timeline = app.buttons["ntv.player.timeline"]
        XCTAssertTrue(focused(timeline, timeout: 5))
        let scrubStart = seconds(quickPosition.label)
        remote.press(.right)
        let position = app.staticTexts["ntv.player.position"].firstMatch
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        let first = position.label
        XCTAssertLessThanOrEqual(abs(seconds(first) - scrubStart - 10), 1,
                                 "Entering the timeline must use the same precise 10-second step as quick skips.")
        remote.press(.right)
        XCTAssertNotEqual(position.label, first, "Right must move the seek preview before committing.")
        let repeatedStart = seconds(position.label)
        for _ in 0..<8 { remote.press(.right) }
        XCTAssertLessThanOrEqual(seconds(position.label) - repeatedStart, 81,
                                 "Rapid presses must never accelerate into minute-sized jumps.")
        capture("ntv-player-seek-preview")
        remote.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        XCTAssertEqual(play.label, "Lecture", "Cancelling a seek must keep a paused video paused.")
        XCTAssertTrue(focused(play, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(app.buttons["ntv.player.info"], timeout: 5), "The information pill must remain reachable below the bar.")
        remote.press(.right)
        let videoTool = app.buttons["ntv.player.video"]
        XCTAssertTrue(focused(videoTool, timeout: 5), "The lower action rail must connect Infos to the video, audio and subtitle tools.")
        XCTAssertGreaterThan(videoTool.frame.minY, timeline.frame.maxY,
                             "Tools belong below the timeline, next to the other lower actions.")
        let toolTop = videoTool.frame.minY
        remote.press(.right)
        let speedTool = app.buttons["ntv.player.speed"]
        XCTAssertTrue(focused(speedTool, timeout: 5))
        remote.press(.select)
        let optionPicker = app.descendants(matching: .any)["ntv.player.picker"].firstMatch
        XCTAssertTrue(optionPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Vitesse de lecture"].exists)
        XCTAssertLessThanOrEqual(optionPicker.frame.maxY, toolTop)
        XCTAssertLessThan(toolTop - optionPicker.frame.maxY, 96)
        capture("ntv-player-speed-near-actions")
        let normalSpeed = app.buttons["ntv.player.picker.item.1.0"]
        XCTAssertTrue(focused(normalSpeed, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(focused(speedTool, timeout: 5), "Choosing a speed must restore its toolbar control.")
        remote.press(.right)
        let subtitlesTool = app.buttons["ntv.player.subtitles"]
        XCTAssertTrue(focused(subtitlesTool, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.buttons["ntv.player.tracks.settings"].waitForExistence(timeout: 5),
                      "Subtitle settings must remain reachable even when the stream has no embedded tracks.")
        let trackPicker = app.descendants(matching: .any)["ntv.player.trackPicker"].firstMatch
        let transport = app.descendants(matching: .any)["ntv.player.transport"].firstMatch
        func assertTrackMenuClearsTransport() {
            XCTAssertTrue(trackPicker.waitForExistence(timeout: 5))
            XCTAssertTrue(transport.exists)
            XCTAssertFalse(trackPicker.frame.intersects(transport.frame),
                           "Audio and subtitle menus must leave the title, timeline, times and tools uncovered.")
            XCTAssertGreaterThanOrEqual(transport.frame.minY - trackPicker.frame.maxY, 16,
                                        "The menu must have a visible gap above the entire transport.")
            XCTAssertLessThanOrEqual(transport.frame.minY - trackPicker.frame.maxY, 48,
                                     "The menu must remain adjacent to the transport, rather than at the top of the screen.")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(trackPicker.frame),
                          "The menu must remain entirely on screen.")
        }
        for identifier in ["earlier", "reset", "later"] {
            let delay = app.buttons["ntv.player.tracks.delay." + identifier]
            XCTAssertTrue(delay.exists, "Quick subtitle timing must be available even without embedded tracks.")
            XCTAssertTrue(trackPicker.frame.contains(delay.frame))
            XCTAssertFalse(delay.frame.intersects(transport.frame))
        }
        capture("ntv-player-subtitle-menu-near-actions")
        assertTrackMenuClearsTransport()
        remote.press(.menu)
        XCTAssertTrue(focused(subtitlesTool, timeout: 5))
        remote.press(.right)
        let audioTool = app.buttons["ntv.player.audio"]
        XCTAssertTrue(focused(audioTool, timeout: 5))
        remote.press(.select)
        capture("ntv-player-audio-near-actions")
        assertTrackMenuClearsTransport()
        remote.press(.menu)
        XCTAssertTrue(focused(audioTool, timeout: 5))
        remote.press(.right)
        let sourcesTool = app.buttons["ntv.player.sources"]
        XCTAssertTrue(focused(sourcesTool, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(optionPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sources"].exists)
        XCTAssertLessThanOrEqual(optionPicker.frame.maxY, toolTop)
        capture("ntv-player-sources-near-actions")
        remote.press(.menu)
        XCTAssertTrue(focused(sourcesTool, timeout: 5), "Back from sources must return to its toolbar control.")
        remote.press(.right)
        XCTAssertTrue(focused(app.buttons["ntv.player.more"], timeout: 5))
        remote.press(.up)
        let runtime = app.buttons["ntv.player.runtime"]
        XCTAssertTrue(focused(runtime, timeout: 5), "The time toggle must be reachable from the rightmost tool.")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(runtime.frame))
        let previousTimeMode = runtime.value as? String
        remote.press(.select)
        XCTAssertNotEqual(runtime.value as? String, previousTimeMode, "Clicking the runtime must toggle elapsed/remaining time.")
        capture("ntv-player-nuvio-remaining-time")
        remote.press(.select)
        XCTAssertEqual(runtime.value as? String, previousTimeMode)
        remote.press(.left)
        XCTAssertTrue(focused(play, timeout: 5))
        remote.press(.up)
        XCTAssertTrue(focused(timeline, timeout: 5))
        remote.press(.select)
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        remote.press(.right)
        remote.press(.select)
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        // Keep the real transport clock mounted while playback continues.
        // Accessibility snapshots can exceed the normal five-second idle
        // dwell; an open track menu keeps chrome visible without pausing or
        // restarting playback and therefore cannot unstick a failed seek.
        remote.press(.down)
        remote.press(.right)
        remote.press(.right)
        remote.press(.right)
        remote.press(.select)
        XCTAssertTrue(trackPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "Lecture", "A seek started while paused must remain paused, as in Nuvio.")
        remote.press(.playPause)
        // Seeking completes asynchronously. Verify the resulting transport
        // state after completion rather than during the demuxer transition.
        let playbackResumed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Pause"), object: play
        )
        XCTAssertEqual(XCTWaiter.wait(for: [playbackResumed], timeout: 8), .completed,
                       "The explicit Play command after a paused seek must resume playback.")
        // An AX snapshot can exceed the predicate deadline before its first evaluation.
        let resumedPosition = transport.staticTexts["ntv.player.position"].firstMatch.label
        Thread.sleep(forTimeInterval: 2)
        let advancedPosition = transport.staticTexts["ntv.player.position"].firstMatch.label
        if advancedPosition == resumedPosition { capture("ntv-player-clock-after-commit-failure") }
        XCTAssertNotEqual(advancedPosition, resumedPosition,
                       "The real playback clock must advance after committing, not just change the button label.")
        // Close the menu and pause before the geometry snapshots. Playback
        // and its advancing clock were checked above while actually running.
        remote.press(.menu)
        remote.press(.playPause)
        XCTAssertEqual(play.label, "Lecture", "Pausing after the successful seek keeps the controls available for inspection.")
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
        app.launchArguments = ["-homeDemo", "-ntvXperienceHomeFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["ntv.home.heading"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ntv.home.spotlight"].waitForExistence(timeout: 80),
                      "Home should display the explicit XPERIENCE native-UI fixture.")
        capture("ntv-home-real-catalogs")
        XCTAssertGreaterThan(app.staticTexts["ntv.home.heading"].frame.minX,
                             app.buttons["ntv.navigation.0"].frame.maxX + 8,
                             "Home must leave horizontal space beside the collapsed left menu.")
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
        XCTAssertTrue(focusedMovie.exists, "The movie posters must remain reachable while the drawer is closed.")
        let initialMovieID = focusedMovie.identifier
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(initialMovieID.dropFirst("ntv.poster.movie.".count))))
        remote.press(.right)
        XCTAssertTrue(focusedMovie.waitForExistence(timeout: 5))
        XCTAssertNotEqual(focusedMovie.identifier, initialMovieID, "Right must select another movie without opening details.")
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(focusedMovie.identifier.dropFirst("ntv.poster.movie.".count))))
        remote.press(.left)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND hasFocus == true", initialMovieID)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(backdropMatches(app, identifier: "ntv.catalog.movie.backdrop",
                                      contentID: String(initialMovieID.dropFirst("ntv.poster.movie.".count))),
                      "Returning left must restore this movie's backdrop, never a stale pending title.")
        // The same title can occur in several category rows. Only one button
        // holds focus, so this query identifies the selected copy unambiguously.
        let selectedPoster = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND hasFocus == true", focusedMovie.identifier)).firstMatch
        capture("ntv-films-real-catalog")
        remote.press(.select)
        XCTAssertTrue(app.descendants(matching: .any)["ntv.detail.screen"].firstMatch.waitForExistence(timeout: 30),
                      "Selecting a poster must open the existing detail screen.")
        let artwork = app.descendants(matching: .any)["ntv.detail.artwork"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let firstArtworkFrame = artwork.frame
        XCTAssertEqual(firstArtworkFrame.height, app.windows.firstMatch.frame.height, accuracy: 2,
                       "A detail must have a full-screen image immediately, before late metadata.")
        capture("ntv-detail-first-viewport")
        capture("ntv-film-detail")
        let play = app.buttons["ntv.detail.play"]
        XCTAssertTrue(focused(play, timeout: 8), "The existing Play control must keep opening focus.")
        XCTAssertEqual(play.label, "Regarder")
        let openingPlayFrame = play.frame
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(artwork.frame, firstArtworkFrame, "The hidden top menu must never resize the detail background.")
        XCTAssertEqual(play.frame.minY, openingPlayFrame.minY, accuracy: 2,
                       "Late metadata must not move the focused action or recenter the page.")
        capture("ntv-detail-settled")
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
        XCTAssertTrue(selectedPoster.waitForExistence(timeout: 8), "Returning from details should restore focus to the selected movie.")
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

    /// Compare settled native focus geometry, never one intermediate platter
    /// animation frame against a fully raised poster. Keep the 2pt assertion.
    private func settledFrame(_ element: XCUIElement, timeout: TimeInterval = 5) -> CGRect {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        var stableSamples = 0
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            let unchanged = abs(current.minX - previous.minX) < 0.5 &&
                abs(current.minY - previous.minY) < 0.5 &&
                abs(current.width - previous.width) < 0.5 &&
                abs(current.height - previous.height) < 0.5
            stableSamples = unchanged ? stableSamples + 1 : 0
            previous = current
            if stableSamples >= 3 { return current }
        }
        XCTFail("Native focus geometry did not settle within the deadline.")
        return previous
    }

    private func focused(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasFocus == true"), object: element
        )
        let completed = XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
        if !completed {
            capture("ntv-focus-failure")
            let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
            hierarchy.name = "ntv-focus-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        return completed
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
