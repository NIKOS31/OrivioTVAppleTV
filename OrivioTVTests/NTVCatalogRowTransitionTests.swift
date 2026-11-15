import XCTest
import Combine
import SwiftUI
import UIKit
@testable import OrivioTV

final class NTVCatalogRowTransitionTests: XCTestCase {
    @MainActor
    func testNativeCatalogRevealKeepsAVisibleRowStillAndRefreshesRetainedContent() async throws {
        let mounted = expectation(description: "First native row mounted")
        let refreshed = expectation(description: "Retained row received the updated content")
        var didMount = false, didRefresh = false
        let controller = NTVNativeCatalogScroll<NativeCatalogProbeRow>.Controller()
        let window = try nativeWindow(controller)
        defer { controller.stop(); window.isHidden = true; window.rootViewController = nil }
        let proxy = NTVCatalogScrollProxy()
        let rows = (0..<8).map { "row-\($0)" }
        controller.update(identifiers: rows, scope: "profile-one", identifier: "native-rows", proxy: proxy,
                          environment: EnvironmentValues()) { id in
            NativeCatalogProbeRow(label: id) { _, _ in
                if id == rows[0], !didMount { didMount = true; mounted.fulfill() }
            }
        }
        await fulfillment(of: [mounted], timeout: 3)
        let collection = try XCTUnwrap(controller.view as? UICollectionView)
        collection.layoutIfNeeded()
        let before = collection.contentOffset
        let first = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertGreaterThan(first.frame.height, 0)
        XCTAssertTrue(collection.bounds.contains(first.frame), "The observed row must already be fully visible.")
        proxy.scrollTo(rows[0])
        XCTAssertEqual(collection.contentOffset.y, before.y, accuracy: 0.5,
                       "Revealing an already visible row must not jump the page to its top.")

        controller.update(identifiers: rows + ["later-row"], scope: "profile-one", identifier: "native-rows",
                          proxy: proxy, environment: EnvironmentValues()) { id in
            NativeCatalogProbeRow(label: "updated-" + id) { label, _ in
                if id == rows[0], label == "updated-" + id, !didRefresh { didRefresh = true; refreshed.fulfill() }
            }
        }
        await fulfillment(of: [refreshed], timeout: 3)
        XCTAssertTrue(didRefresh, "Adding another row must not leave retained rows with old actions or content.")
    }

    @MainActor
    func testNativeCatalogScopeReplacementDropsPendingRevealAndUpdatesEnvironment() async throws {
        let mounted = expectation(description: "Initial native row mounted")
        let replaced = expectation(description: "New profile environment reached the native row")
        var didMount = false, didReplace = false
        let controller = NTVNativeCatalogScroll<NativeCatalogProbeRow>.Controller()
        let window = try nativeWindow(controller)
        defer { controller.stop(); window.isHidden = true; window.rootViewController = nil }
        let proxy = NTVCatalogScrollProxy()
        let rows = (0..<8).map { "row-\($0)" }
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "fr_FR")
        controller.update(identifiers: rows, scope: "profile-one", identifier: "native-rows", proxy: proxy,
                          environment: environment) { id in
            NativeCatalogProbeRow(label: id) { _, locale in
                if id == rows[0], locale == "fr_FR", !didMount { didMount = true; mounted.fulfill() }
            }
        }
        await fulfillment(of: [mounted], timeout: 3)
        let collection = try XCTUnwrap(controller.view as? UICollectionView)
        collection.layoutIfNeeded()
        let before = collection.contentOffset
        proxy.scrollTo("later-row", anchor: .top)
        environment.locale = Locale(identifier: "en_GB")
        controller.update(identifiers: rows + ["later-row"], scope: "profile-two", identifier: "native-rows",
                          proxy: proxy, environment: environment) { id in
            NativeCatalogProbeRow(label: id) { _, locale in
                if id == rows[0], locale == "en_GB", !didReplace { didReplace = true; replaced.fulfill() }
            }
        }
        await fulfillment(of: [replaced], timeout: 3)
        collection.layoutIfNeeded()
        XCTAssertEqual(collection.contentOffset.y, before.y, accuracy: 0.5,
                       "A new profile must not replay the former profile's pending scroll.")
        XCTAssertTrue(didReplace)
    }

    @MainActor
    func testDismantlingAnOldNativeCatalogCannotDetachItsReplacement() async throws {
        let mounted = expectation(description: "Replacement native catalog mounted")
        var didMount = false
        let old = NTVNativeCatalogScroll<NativeCatalogProbeRow>.Controller()
        let replacement = NTVNativeCatalogScroll<NativeCatalogProbeRow>.Controller()
        let window = try nativeWindow(replacement)
        defer { old.stop(); replacement.stop(); window.isHidden = true; window.rootViewController = nil }
        let proxy = NTVCatalogScrollProxy()
        old.update(identifiers: ["old"], scope: "old", identifier: "native-old", proxy: proxy,
                   environment: EnvironmentValues()) { id in NativeCatalogProbeRow(label: id) { _, _ in } }
        let rows = (0..<12).map { "row-\($0)" }
        replacement.update(identifiers: rows, scope: "replacement", identifier: "native-new", proxy: proxy,
                           environment: EnvironmentValues()) { id in
            NativeCatalogProbeRow(label: id) { _, _ in
                if id == rows[0], !didMount { didMount = true; mounted.fulfill() }
            }
        }
        await fulfillment(of: [mounted], timeout: 3)
        let collection = try XCTUnwrap(replacement.view as? UICollectionView)
        collection.layoutIfNeeded()
        let before = collection.contentOffset
        old.stop()
        proxy.scrollTo(try XCTUnwrap(rows.last), anchor: .top)
        collection.layoutIfNeeded()
        XCTAssertGreaterThan(collection.contentOffset.y, before.y,
                             "The replacement must still receive scroll requests after the old controller exits.")
        let last = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: rows.count - 1, section: 0)))
        XCTAssertTrue(collection.bounds.intersects(last.frame))
    }

    @MainActor
    private func nativeWindow(_ controller: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1200, height: 720)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    func testCatalogScopeReplacementCancelsOnlyItsOwnPendingEntry() throws {
        let model = try browser()
        let source = model.sources[0]
        let router = ContentFocusRouter.shared
        router.cancelLanding()
        defer { router.cancelLanding() }
        let own = router.makeEntryRequest(in: "ntv.catalog.shelf." + source.id, kind: .orderedRow)
        model.requestedCategory = .init(sourceID: source.id, entry: own)
        model.configure(addons: [source.addon], type: "movie", scope: "entry-fixture")
        XCTAssertTrue(router.isPendingEntry(own), "Reappearing with the same scope must not cancel focus restoration or entry.")
        model.configure(addons: [source.addon], type: "movie", scope: "profile-two")
        XCTAssertFalse(router.isPendingEntry(own))
        XCTAssertNil(model.requestedCategory)

        let older = router.makeEntryRequest(in: "ntv.catalog.shelf." + source.id, kind: .orderedRow)
        model.requestedCategory = .init(sourceID: source.id, entry: older)
        let newer = router.makeEntryRequest(in: "ntv.catalog.series.entry", kind: .restoration)
        model.configure(addons: [source.addon], type: "movie", scope: "profile-three")
        XCTAssertTrue(router.isPendingEntry(newer), "A scope replacement may retire its own entry, never a newer page's request.")
        XCTAssertNil(model.requestedCategory)
    }

    @MainActor
    func testCatalogEntryPublishesOnlyDepartingAndDestinationShelves() throws {
        let model = try browser()
        let shelves = model.sources.map { model.shelf($0) }
        let router = ContentFocusRouter()
        var browserUpdates = 0, shelfUpdates = [0, 0, 0]
        let observations = [model.objectWillChange.sink { _ in browserUpdates += 1 }]
            + shelves.enumerated().map { index, shelf in
                shelf.$focusRequest.dropFirst().sink { _ in shelfUpdates[index] += 1 }
            }
        defer { observations.forEach { $0.cancel() } }
        let first = NTVCatalogBrowserModel.FocusRequest(sourceID: model.sources[0].id,
            entry: router.makeEntryRequest(in: "ntv.catalog.shelf.first"), scrollToStart: false)
        model.requestedCategory = first
        model.requestedCategory = first
        XCTAssertEqual(shelves[0].focusRequest, first)
        XCTAssertEqual(shelfUpdates, [1, 0, 0], "An unchanged request must not republish its shelf.")

        let next = NTVCatalogBrowserModel.FocusRequest(sourceID: model.sources[1].id,
            entry: router.makeEntryRequest(in: "ntv.catalog.shelf.second", kind: .orderedRow))
        model.requestedCategory = next
        XCTAssertNil(shelves[0].focusRequest)
        XCTAssertEqual(shelves[1].focusRequest, next)
        XCTAssertEqual(shelfUpdates, [2, 1, 0], "Only the departing and destination shelves need new entry inputs.")
        model.requestedCategory = nil
        XCTAssertNil(shelves[1].focusRequest)
        XCTAssertEqual(shelfUpdates, [2, 2, 0])
        XCTAssertEqual(browserUpdates, 0, "Entry changes must not invalidate every shelf through the browser.")
    }

    @MainActor
    func testCatalogEntryReachesALaterMountedShelfAndClearsWithItsScope() throws {
        let model = try browser()
        let source = model.sources[1]
        let router = ContentFocusRouter()
        let request = NTVCatalogBrowserModel.FocusRequest(sourceID: source.id,
            entry: router.makeEntryRequest(in: "ntv.catalog.shelf.later", kind: .orderedRow), scrollToStart: false)
        model.requestedCategory = request
        let mounted = model.shelf(source)
        XCTAssertEqual(mounted.focusRequest, request, "A lazy destination must receive an entry requested before it mounted.")
        model.configure(addons: [source.addon], type: "movie", scope: "entry-fixture")
        XCTAssertTrue(mounted === model.shelf(source))
        XCTAssertEqual(mounted.focusRequest, request, "An unchanged scope must retain its pending entry.")

        router.cancelEntry(model.requestedCategory?.entry)
        model.configure(addons: [source.addon], type: "movie", scope: "another-profile")
        XCTAssertFalse(router.consumeEntry(request.entry))
        XCTAssertNil(model.requestedCategory)
        XCTAssertNil(mounted.focusRequest)
        let remounted = model.shelf(source)
        XCTAssertFalse(mounted === remounted)
        XCTAssertNil(remounted.focusRequest, "A replaced scope must not replay the previous profile's entry.")
    }

    @MainActor
    private func browser() throws -> NTVCatalogBrowserModel {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"entry-fixture","name":"Fixture","version":"1","types":["movie"],"resources":["catalog"],"catalogs":[{"type":"movie","id":"first"},{"type":"movie","id":"second"},{"type":"movie","id":"third"}]}"#.utf8))
        let model = NTVCatalogBrowserModel()
        model.configure(addons: [InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)],
            type: "movie", scope: "entry-fixture")
        return model
    }

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

private struct NativeCatalogProbeRow: View {
    @Environment(\.locale) private var locale
    let label: String
    let rendered: (String, String) -> Void
    var body: some View {
        Text(label).frame(maxWidth: .infinity).frame(height: 160)
            .onAppear { rendered(label, locale.identifier) }
            .onChange(of: label) { _, _ in rendered(label, locale.identifier) }
            .onChange(of: locale.identifier) { _, _ in rendered(label, locale.identifier) }
    }
}
