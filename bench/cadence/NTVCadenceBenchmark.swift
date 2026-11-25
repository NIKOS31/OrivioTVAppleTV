import XCTest

/// Benchmark-only (perf/ntv-cadence-*), outside the qualification manifest.
/// Same fixture, theme and remote sequence for 56 and 57. During a measured
/// sequence the test sends presses at a fixed pace and makes no accessibility
/// query, so XCTest's own snapshots stay outside the measured windows.
/// Simulator, Debug: compares versions, never stands for the Apple TV.
final class NTVCadenceBenchmark: XCTestCase {
    private let catalogArgs = ["-homeDemo", "-ntvSeanimeDemo", "-ntvCatalogCategoriesDemo",
                               "-ntvRowLayoutFixture", "-ntvCatalogThreeRowsFixture",
                               "-orivio.diag.capture.v1", "YES", "-ntvCadenceProbe"]
    private let repeats = 3
    private let pace: TimeInterval = 0.5

    func testFilmsVertical() throws {
        let app = launch(catalogArgs)
        let rows = try enterMovies(app)
        try measure(app, "films.vertical", [.down, .down, .up, .up], home: rows[0], warmUp: rows)
    }

    func testFilmsHorizontal() throws {
        let app = launch(catalogArgs)
        let rows = try enterMovies(app)
        let row = (0..<7).map { app.buttons["ntv.poster.movie.fixture.catalog.fixture-row-0.\($0)"] }
        try measure(app, "films.horizontal", Array(repeating: .right, count: 6) + Array(repeating: .left, count: 6),
                    home: rows[0], warmUp: row)
    }

    func testSeriesVertical() throws {
        let app = launch(catalogArgs)
        _ = try enterMovies(app)
        let remote = XCUIRemote.shared
        let movies = app.buttons["ntv.navigation.5"]
        for _ in 0..<3 {
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.down)
        XCTAssertTrue(focused(app.buttons["ntv.navigation.6"], timeout: 5))
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["ntv.catalog.series.heading"].waitForExistence(timeout: 20))
        let rows = (0..<3).map { app.buttons["ntv.poster.series.fixture.catalog.fixture-row-\($0).0"] }
        XCTAssertTrue(focused(rows[0], timeout: 8))
        try measure(app, "series.vertical", [.down, .down, .up, .up], home: rows[0], warmUp: rows)
    }

    func testHomeVertical() throws {
        let app = launch(["-homeDemo", "-ntvTopMenuDemo", "-ntvRowLayoutFixture", "-ntvSeanimeDemo",
                          "-orivio.diag.capture.v1", "YES", "-ntvCadenceProbe"])
        let rows = try enterHome(app)
        try measure(app, "home.vertical", [.down, .down, .up, .up], home: rows[0], warmUp: rows)
    }

    func testHomeHorizontal() throws {
        let app = launch(["-homeDemo", "-ntvTopMenuDemo", "-ntvRowLayoutFixture", "-ntvSeanimeDemo",
                          "-orivio.diag.capture.v1", "YES", "-ntvCadenceProbe"])
        let rows = try enterHome(app)
        let row = (0..<7).map { app.buttons["ntv.home.poster.movie.fixture.row.0.item.\($0)"] }
        try measure(app, "home.horizontal", Array(repeating: .right, count: 6) + Array(repeating: .left, count: 6),
                    home: rows[0], warmUp: row)
    }

    // MARK: - Navigation (same paths as NTVDesignSmoke)

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["MTL_DEBUG_LAYER"] = "0"
        app.launchEnvironment["MTL_SHADER_VALIDATION"] = "0"
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    private func enterMovies(_ app: XCUIApplication) throws -> [XCUIElement] {
        let remote = XCUIRemote.shared
        let rows = (0..<3).map { app.buttons["ntv.poster.movie.fixture.catalog.fixture-row-\($0).0"] }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 20))
        let movies = app.buttons["ntv.navigation.5"]
        for _ in 0..<3 {
            if movies.hasFocus { break }
            remote.press(.menu)
            if focused(movies, timeout: 2) { break }
        }
        XCTAssertTrue(focused(movies, timeout: 5))
        remote.press(.right)
        XCTAssertTrue(focused(rows[0], timeout: 8))
        return rows
    }

    private func enterHome(_ app: XCUIApplication) throws -> [XCUIElement] {
        let remote = XCUIRemote.shared
        let settings = app.buttons["ntv.navigation.3"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        remote.press(.menu)
        XCTAssertTrue(focused(settings, timeout: 8))
        for _ in 0..<9 {
            if app.buttons["ntv.navigation.0"].hasFocus { break }
            remote.press(.up)
        }
        XCTAssertTrue(focused(app.buttons["ntv.navigation.0"], timeout: 5))
        remote.press(.select)
        remote.press(.right)
        XCTAssertTrue(app.buttons["ntv.home.spotlight"].waitForExistence(timeout: 15))
        let firstShelfFocus = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND hasFocus == true",
            "ntv.home.poster.movie.fixture.row.0.item.")).firstMatch
        for _ in 0..<6 {
            if firstShelfFocus.exists { break }
            remote.press(.down)
        }
        XCTAssertTrue(firstShelfFocus.exists)
        let rows = (0..<3).map { app.buttons["ntv.home.poster.movie.fixture.row.\($0).item.0"] }
        for _ in 0..<24 {
            if rows[0].hasFocus { break }
            remote.press(.left)
        }
        XCTAssertTrue(focused(rows[0], timeout: 8))
        return rows
    }

    // MARK: - Measurement

    /// warmUp: every destination visited once with focus checks, so the
    /// measured passes see already mounted shelves and loaded placeholders.
    private func measure(_ app: XCUIApplication, _ segment: String, _ moves: [XCUIRemote.Button],
                         home: XCUIElement, warmUp: [XCUIElement]) throws {
        let remote = XCUIRemote.shared
        let forward: XCUIRemote.Button = moves[0], back: XCUIRemote.Button = moves.last!
        for target in warmUp.dropFirst() {
            remote.press(forward)
            XCTAssertTrue(focused(target, timeout: 8), "\(segment): warm-up did not reach \(target.identifier)")
        }
        for _ in warmUp.dropFirst() { remote.press(back) }
        XCTAssertTrue(focused(home, timeout: 8))
        var passes: [[String: Any]] = []
        for pass in 0..<repeats {
            Thread.sleep(forTimeInterval: 1.5)
            let before = try probe(app)
            let readReturned = Date()
            // Windows that started within 1 s of a read contain its accessibility work.
            Thread.sleep(forTimeInterval: 2.5)
            let movesStarted = Date()
            for move in moves {
                remote.press(move)
                Thread.sleep(forTimeInterval: pace)
            }
            let movesSeconds = Date().timeIntervalSince(movesStarted)
            // App clock at the end of the presses, mapped from the first read (conservative).
            let movesEndApp = before.now + Date().timeIntervalSince(readReturned)
            Thread.sleep(forTimeInterval: 2.0)
            let after = try probe(app)
            // Validity, checked only after the reading: the sequence returns home.
            XCTAssertTrue(focused(home, timeout: 8), "\(segment) pass \(pass): sequence did not end on its start poster")
            let windows = after.windows.filter { $0.start >= before.now + 1.0 && $0.end <= movesEndApp + 1.5 }
            XCTAssertGreaterThanOrEqual(windows.reduce(0) { $0 + $1.duration }, movesSeconds,
                                        "\(segment) pass \(pass): cadence windows must cover the presses")
            var work: [String: [String: Double]] = [:]
            for (scope, value) in after.work {
                let old = before.work[scope] ?? (0, 0)
                work[scope] = ["evaluations": value.0 - old.0, "milliseconds": value.1 - old.1]
            }
            passes.append([
                "pass": pass, "presses": moves.count, "paceSeconds": pace, "pressSeconds": movesSeconds,
                "windows": windows.map { ["duration": $0.duration, "callbacks": $0.callbacks,
                                          "worstGapMs": $0.worstGapMs, "late": $0.late] as [String: Any] },
                "worstGapMs": windows.map(\.worstGapMs).max() ?? 0,
                "lateCallbacks": windows.reduce(0) { $0 + $1.late },
                "callbacks": windows.reduce(0) { $0 + $1.callbacks },
                "seconds": windows.reduce(0) { $0 + $1.duration },
                "droppedRecords": after.dropped,
                "workDelta": work,
            ])
        }
        let json = try JSONSerialization.data(withJSONObject: ["segment": segment, "passes": passes],
                                              options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = "ntv-cadence-\(segment)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Window { let end, duration: Double; let callbacks: Int; let worstGapMs: Double; let late: Int
        var start: Double { end - duration } }
    private struct Reading { let now: Double; let dropped: Int; let windows: [Window]; let work: [String: (Double, Double)] }

    private func probe(_ app: XCUIApplication) throws -> Reading {
        let element = app.descendants(matching: .any)["ntv.bench.cadence"].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "The benchmark probe must be installed.")
        let raw = try XCTUnwrap(element.value as? String)
        let parts = raw.components(separatedBy: "|")
        XCTAssertEqual(parts.count, 4, "Unexpected probe format")
        let now = try XCTUnwrap(Double(parts[0].replacingOccurrences(of: "now=", with: "")))
        let dropped = try XCTUnwrap(Int(parts[1].replacingOccurrences(of: "dropped=", with: "")))
        let windows = try parts[2].split(separator: ";").map { record -> Window in
            let f = record.split(separator: ",").map(String.init)
            XCTAssertEqual(f.count, 5)
            return Window(end: try XCTUnwrap(Double(f[0])), duration: try XCTUnwrap(Double(f[1])),
                          callbacks: try XCTUnwrap(Int(f[2])), worstGapMs: try XCTUnwrap(Double(f[3])),
                          late: try XCTUnwrap(Int(f[4])))
        }
        var work: [String: (Double, Double)] = [:]
        for entry in parts[3].split(separator: ",") {
            let kv = entry.split(separator: "=", maxSplits: 1).map(String.init)
            let nums = kv[1].split(separator: "/").compactMap { Double($0) }
            if nums.count == 2 { work[kv[0]] = (nums[0], nums[1]) }
        }
        return Reading(now: now, dropped: dropped, windows: windows, work: work)
    }

    private func focused(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"),
                                                       object: element)], timeout: timeout) == .completed
    }
}
