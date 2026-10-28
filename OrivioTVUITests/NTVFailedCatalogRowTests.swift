import XCTest

final class NTVFailedCatalogRowTests: XCTestCase {
    func testRetryReceivesFocusAndYieldsToNeighborCommands() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-homeDemo", "-ntvTopMenuDemo", "-ntvCatalogCategoriesDemo",
                               "-ntvCatalogThreeRowsFixture", "-ntvRowLayoutFixture", "-ntvCatalogRetryFixture"]
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let first = app.buttons["ntv.poster.movie.fixture.catalog.fixture-row-0.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        let movies = app.buttons["ntv.navigation.5"]
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(first, timeout: 8))
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ntv.catalog.retry.")).firstMatch
        remote.press(.down)
        XCTAssertTrue(focused(retry, timeout: 8), "A failed shelf must land on its usable Retry action.")
        remote.press(.up)
        XCTAssertTrue(focused(first, timeout: 8), "Up from Retry must enter the previous shelf at its first poster.")
        remote.press(.down)
        XCTAssertTrue(focused(retry, timeout: 8))
        remote.press(.select)
        XCTAssertTrue(focused(retry, timeout: 8), "A failed retry must keep its action reachable.")
        remote.press(.down)
        let nextFirst = app.buttons["ntv.poster.movie.fixture.catalog.fixture-row-2.0"]
        XCTAssertTrue(focused(nextFirst, timeout: 8), "Down from Retry must enter the next shelf at its first poster.")
        remote.press(.right)
        let nextSecond = app.buttons["ntv.poster.movie.fixture.catalog.fixture-row-2.1"]
        XCTAssertTrue(focused(nextSecond, timeout: 5))
        let oldRowReclaimsFocus = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: retry)
        oldRowReclaimsFocus.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [oldRowReclaimsFocus], timeout: 0.5), .completed)
        XCTAssertTrue(nextSecond.hasFocus, "The previous failed row must not reclaim focus after a new command.")
    }

    private func focused(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
