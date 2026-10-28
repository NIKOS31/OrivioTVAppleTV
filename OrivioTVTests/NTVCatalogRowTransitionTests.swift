import XCTest
@testable import OrivioTV

final class NTVCatalogRowTransitionTests: XCTestCase {
    @MainActor
    func testOrderedRowEntrySurvivesAnIntermediateNativeCandidate() {
        let router = ContentFocusRouter()
        let target = "ntv.catalog.shelf.neighbor"
        let request = router.makeEntryRequest(in: target, kind: .orderedRow)

        router.noteFocused(row: "ntv.catalog.shelf.intermediate")

        XCTAssertTrue(router.isPendingEntry(request), "A scroll's native candidate cannot discard the commanded neighbor before its task mounts.")
        XCTAssertEqual(router.movingToRowID, target, "Intermediate candidates must not trigger another row reset.")
        XCTAssertTrue(router.consumeEntry(request))
        XCTAssertFalse(router.consumeEntry(request), "Remounting must not replay the same transition.")
    }

    @MainActor
    func testOrderedRowLandingKeepsItsDestinationUntilNativeFocusConfirmsIt() async throws {
        let router = ContentFocusRouter()
        defer { router.cancelLanding() }
        let target = "ntv.catalog.shelf.neighbor"
        var assignments = 0, landed = false
        router.land(in: target, kind: .orderedRow,
                    assign: { assignments += 1 }, landed: { landed },
                    focusToken: { "native-remembered-poster" })

        router.noteFocused(row: "ntv.catalog.shelf.intermediate")
        XCTAssertEqual(router.movingToRowID, target)
        try await until { assignments > 3 }

        landed = true
        router.noteFocused(row: target)
        try await until { router.movingToRowID == nil }
        XCTAssertEqual(router.lastRowID, target)
    }

    @MainActor
    func testANewCommandInAnIntermediateRowCancelsTheOrderedTransition() async throws {
        let router = ContentFocusRouter()
        let target = "ntv.catalog.shelf.neighbor", intermediate = "ntv.catalog.shelf.intermediate"
        let request = router.makeEntryRequest(in: target, kind: .orderedRow)
        router.noteFocused(row: intermediate)
        router.noteUserMovement(in: intermediate)
        XCTAssertFalse(router.consumeEntry(request))
        XCTAssertNil(router.movingToRowID)

        var assignments = 0
        router.land(in: target, kind: .orderedRow,
                    assign: { assignments += 1 }, landed: { false })
        router.noteUserMovement(in: intermediate)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(assignments, 1, "The superseded row must never reclaim focus after a newer command.")
        XCTAssertNil(router.movingToRowID)
    }

    @MainActor
    func testOrderedRowEntryStillYieldsToPageExitAndUnmount() {
        let router = ContentFocusRouter()
        let target = "ntv.catalog.shelf.neighbor"
        let leaving = router.makeEntryRequest(in: target, kind: .orderedRow)
        router.noteFocused(row: "ntv.catalog.series.entry")
        XCTAssertFalse(router.consumeEntry(leaving))

        let unmounting = router.makeEntryRequest(in: target, kind: .orderedRow)
        router.unregister(target)
        XCTAssertFalse(router.consumeEntry(unmounting))
        XCTAssertNil(router.movingToRowID)

        let ordinary = router.makeEntryRequest(in: target)
        router.noteFocused(row: "ntv.catalog.shelf.other")
        XCTAssertFalse(router.consumeEntry(ordinary), "An ordinary entry retains its existing cancellation contract.")
    }

    @MainActor
    private func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "The existing landing loop did not reach the expected state.")
    }
}
