import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Combine
@testable import OrivioTV

final class NTVPerformanceTests: XCTestCase {
    @MainActor
    func testHiddenHomeSpotlightDoesNotPublishOrEnrichEveryFocusStep() async throws {
        let hero = HeroFocus()
        hero.suspendsWhenOffscreen = true
        hero.layout = .pinnedFocus
        let initial = MetaItem(id: "visible", type: "movie", name: "Visible", description: "Ready")
        hero.item = initial
        var updates = 0, enrichments = 0
        let observation = hero.$item.dropFirst().sink { _ in updates += 1 }
        defer { observation.cancel() }
        hero.enrich = { _ in enrichments += 1; return nil }
        hero.setPresentationActive(false)
        for index in 0..<80 {
            hero.focus(MetaItem(id: "hidden.\(index)", type: "movie", name: "Hidden \(index)"))
        }
        await Task.yield()
        XCTAssertEqual(hero.item?.id, initial.id)
        XCTAssertEqual(updates, 0, "Offscreen rows must not republish a hidden banner or its full-screen artwork.")
        XCTAssertEqual(enrichments, 0)
        hero.setPresentationActive(true)
        try await until { hero.item?.id == "hidden.79" && enrichments == 1 }
        XCTAssertEqual(updates, 1, "Restore only the newest focused title when the banner is visible again.")
    }

    @MainActor
    func testHidingHomeSpotlightCancelsAnAlreadyScheduledFocusCommit() async throws {
        let hero = HeroFocus()
        hero.suspendsWhenOffscreen = true
        hero.layout = .pinnedFocus
        hero.item = MetaItem(id: "visible", type: "movie", name: "Visible", description: "Ready")
        hero.focus(MetaItem(id: "pending", type: "movie", name: "Pending", description: "Ready"))
        hero.setPresentationActive(false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(hero.item?.id, "visible", "Leaving the viewport cancels work already waiting in the focus debounce.")
        hero.setPresentationActive(true)
        try await until { hero.item?.id == "pending" }
    }

    @MainActor
    func testSpotlightPauseDwellAndManualNavigation() throws {
        try XCTSkipIf(PerformanceSettingsStore.shared.reduceMotion)
        let hero = HeroFocus()
        hero.setSpotlight([MetaItem(id: "first", type: "movie", name: "First"),
                           MetaItem(id: "second", type: "movie", name: "Second")])
        let later = Date().addingTimeInterval(30)
        hero.spotlightPaused = true
        hero.rotateIfIdle(now: later)
        XCTAssertEqual(hero.spotlightIndex, 0)
        hero.spotlightPaused = false
        hero.rotateIfIdle(now: later)
        XCTAssertEqual(hero.spotlightIndex, 1)
        hero.rotateIfIdle(now: later.addingTimeInterval(5))
        XCTAssertEqual(hero.spotlightIndex, 1, "Keep each proposal readable for the full dwell.")
        hero.spotlightPaused = true
        hero.stepSpotlight(by: 1)
        XCTAssertEqual(hero.spotlightIndex, 0, "Manual navigation must still work while paused.")
    }

    func testRenderMeterSeparatesBodyCountsFromTimedWorkAndRejectsInvalidDurations() throws {
        let meter = NTVRenderMeter()
        meter.record(.posterRow); meter.record(.posterRow)
        meter.record(.posterEligibility, milliseconds: 2)
        meter.record(.posterEligibility, milliseconds: 4)
        meter.record(.posterEligibility, milliseconds: .nan)
        meter.record(.posterEligibility, milliseconds: -1)
        let snapshot = meter.snapshot()
        let body = try XCTUnwrap(snapshot[.posterRow]), filter = try XCTUnwrap(snapshot[.posterEligibility])
        XCTAssertEqual(body.evaluations, 2)
        XCTAssertEqual(body.timedEvaluations, 0, "A body evaluation count must not be presented as frame duration.")
        XCTAssertEqual(filter.evaluations, 2)
        XCTAssertEqual(filter.totalMilliseconds, 6)
        XCTAssertEqual(filter.maximumMilliseconds, 4)
        meter.reset()
        XCTAssertTrue(meter.snapshot().isEmpty)
    }

    func testRenderMeterCountsConcurrentWorkWithoutGrowingPerItemEntries() {
        let meter = NTVRenderMeter()
        DispatchQueue.concurrentPerform(iterations: 512) { _ in meter.record(.posterCell) }
        let snapshot = meter.snapshot()
        XCTAssertEqual(snapshot[.posterCell]?.evaluations, 512)
        XCTAssertEqual(snapshot.count, 1, "The store has fixed scopes, not a new entry for every poster or evaluation.")
    }

    func testPosterVisibilityDoesNotReclassifyContentDuringFocusSteps() {
        let items = (0..<16).map { MetaItem(id: "fixture.\($0)", type: "movie", name: "Fixture \($0)") }
        var classifications = 0
        let snapshot = NTVPosterVisibility(items: items, hideUnreleased: false, hideUnavailable: false,
            unavailableUntil: [:], now: Date()) { _ in classifications += 1; return false }
        for step in 0..<160 {
            XCTAssertEqual(snapshot.items(keeping: items[step % items.count].id).count, 16)
        }
        XCTAssertEqual(classifications, 16, "Local focus steps must not repeat anime classification or title filtering.")
    }

    func testPosterVisibilityPinsOnlyTheFocusedUnavailableItemAndExpiresOnTime() {
        let items = ["a", "b", "c", "d"].map { MetaItem(id: $0, type: "movie", name: $0) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let absence = ["b": now.addingTimeInterval(10), "c": now.addingTimeInterval(20)]
        func snapshot(at date: Date) -> NTVPosterVisibility {
            NTVPosterVisibility(items: items, hideUnreleased: false, hideUnavailable: true,
                unavailableUntil: absence, now: date, isAnime: { _ in false })
        }
        let initial = snapshot(at: now)
        XCTAssertEqual(initial.items(keeping: nil).map(\.id), ["a", "d"])
        XCTAssertEqual(initial.items(keeping: "b").map(\.id), ["a", "b", "d"])
        XCTAssertEqual(initial.items(keeping: "c").map(\.id), ["a", "c", "d"])
        XCTAssertEqual(initial.items(keeping: "d").map(\.id), ["a", "d"])
        XCTAssertEqual(initial.nextRefresh, absence["b"])
        let firstExpiry = snapshot(at: now.addingTimeInterval(10))
        XCTAssertEqual(firstExpiry.items(keeping: nil).map(\.id), ["a", "b", "d"])
        XCTAssertEqual(firstExpiry.nextRefresh, absence["c"])
        let expired = snapshot(at: now.addingTimeInterval(20))
        XCTAssertEqual(expired.items(keeping: nil).map(\.id), ["a", "b", "c", "d"])
        XCTAssertNil(expired.nextRefresh)
    }

    func testPosterVisibilityNeverPinsAnimeOrAnUnreleasedTitle() throws {
        let now = try XCTUnwrap(ReleaseDateParser.parse("2026-10-17T12:00:00Z"))
        let items = [MetaItem(id: "anime", type: "series", name: "Anime"),
            MetaItem(id: "future", type: "movie", name: "Future", released: "2027-01-10T12:00:00Z"),
            MetaItem(id: "unknown", type: "movie", name: "Unknown date")]
        let hidden = NTVPosterVisibility(items: items, hideUnreleased: true, hideUnavailable: true,
            unavailableUntil: [:], now: now, isAnime: { $0.id == "anime" })
        XCTAssertEqual(hidden.items(keeping: "anime").map(\.id), ["unknown"])
        XCTAssertEqual(hidden.items(keeping: "future").map(\.id), ["unknown"])
        XCTAssertEqual(hidden.nextRefresh, ReleaseDateParser.parse("2027-01-10T12:00:00Z"))
        let shown = NTVPosterVisibility(items: items, hideUnreleased: false, hideUnavailable: false,
            unavailableUntil: [:], now: now, isAnime: { $0.id == "anime" })
        XCTAssertEqual(shown.items(keeping: nil).map(\.id), ["future", "unknown"])
    }

    func testPosterVisibilityRechecksExactDatesAndBareYearBoundaries() throws {
        let release = try XCTUnwrap(ReleaseDateParser.parse("2026-10-18T18:30:00Z"))
        let dated = MetaItem(id: "dated", type: "movie", name: "Dated", released: "2026-10-18T18:30:00Z")
        let before = NTVPosterVisibility(items: [dated], hideUnreleased: true, hideUnavailable: false,
            unavailableUntil: [:], now: release.addingTimeInterval(-1), isAnime: { _ in false })
        XCTAssertTrue(before.items(keeping: nil).isEmpty); XCTAssertEqual(before.nextRefresh, release)
        let after = NTVPosterVisibility(items: [dated], hideUnreleased: true, hideUnavailable: false,
            unavailableUntil: [:], now: release, isAnime: { _ in false })
        XCTAssertEqual(after.items(keeping: nil).map(\.id), ["dated"])
        XCTAssertNil(after.nextRefresh)
        let newYear = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let yearly = MetaItem(id: "yearly", type: "movie", name: "Year", releaseInfo: "2027")
        let lastYear = NTVPosterVisibility(items: [yearly], hideUnreleased: true, hideUnavailable: false,
            unavailableUntil: [:], now: newYear.addingTimeInterval(-1), isAnime: { _ in false })
        XCTAssertTrue(lastYear.items(keeping: nil).isEmpty); XCTAssertEqual(lastYear.nextRefresh, newYear)
        let thisYear = NTVPosterVisibility(items: [yearly], hideUnreleased: true, hideUnavailable: false,
            unavailableUntil: [:], now: newYear, isAnime: { _ in false })
        XCTAssertEqual(thisYear.items(keeping: nil).map(\.id), ["yearly"])
    }

    func testPosterVisibilityRebuildHonorsNewClassificationAndFiltersInSourceOrder() {
        let items = ["z", "a", "m"].map { MetaItem(id: $0, type: "movie", name: $0) }
        let now = Date()
        let first = NTVPosterVisibility(items: items, hideUnreleased: false, hideUnavailable: false,
            unavailableUntil: ["a": now.addingTimeInterval(60)], now: now, isAnime: { _ in false })
        XCTAssertEqual(first.items(keeping: nil).map(\.id), ["z", "a", "m"])
        let changed = NTVPosterVisibility(items: items, hideUnreleased: false, hideUnavailable: true,
            unavailableUntil: ["a": now.addingTimeInterval(60)], now: now, isAnime: { $0.id == "z" })
        XCTAssertEqual(changed.items(keeping: nil).map(\.id), ["m"])
        XCTAssertEqual(changed.items(keeping: "a").map(\.id), ["a", "m"])
    }

    @MainActor
    func testInitialHomeFocusAppliesOnceWhenItsContextIsStillCurrent() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var applied = 0
        let pending = request.schedule(router: router, hero: hero, isEligible: { true }) { applied += 1 }
        try await until { await gate.started.count == 1 }
        XCTAssertEqual(applied, 0, "Initial focus waits for the view to settle.")
        await gate.release("seed")
        await pending.value
        XCTAssertEqual(applied, 1)
    }

    @MainActor
    func testInitialHomeFocusCannotOverrideNewerNavigation() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var applied = false
        let pending = request.schedule(router: router, hero: hero, isEligible: { true }) { applied = true }
        try await until { await gate.started.count == 1 }
        router.noteUserMovement()
        await gate.release("seed")
        await pending.value
        XCTAssertFalse(applied, "An older initial landing must not reclaim focus after opening a menu or changing tabs.")
    }

    @MainActor
    func testInitialHomeFocusCannotOverrideAChangedRowWithoutAMoveCommand() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        router.noteFocused(row: "home.heroPlay")
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var applied = false
        let pending = request.schedule(router: router, hero: hero, isEligible: { true }) { applied = true }
        try await until { await gate.started.count == 1 }
        router.noteFocused(row: "home.poster.row")
        await gate.release("seed")
        await pending.value
        XCTAssertFalse(applied, "A native row entry can supersede the request without a bubbled remote command.")
    }

    @MainActor
    func testInitialHomeFocusRejectsAnInteractionEvenAfterReturningToTheSameRow() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        hero.layout = .rolling
        router.noteFocused(row: "home.heroPlay")
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var applied = false
        let pending = request.schedule(router: router, hero: hero, isEligible: { true }) { applied = true }
        try await until { await gate.started.count == 1 }
        hero.focus(MetaItem(id: "another-title", type: "movie", name: "Another title"))
        router.noteFocused(row: "home.poster.row")
        router.noteFocused(row: "home.heroPlay")
        await gate.release("seed")
        await pending.value
        XCTAssertFalse(applied, "Returning to the same row must not make an obsolete request current again.")
    }

    @MainActor
    func testInitialHomeFocusCancellationWinsEvenWhenItsWaitIgnoresCancellation() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var applied = false
        let pending = request.schedule(router: router, hero: hero, isEligible: { true }) { applied = true }
        try await until { await gate.started.count == 1 }
        request.cancel()
        // The gate deliberately resumes successfully after cancellation.
        await gate.release("seed")
        await pending.value
        XCTAssertFalse(applied, "Disappearance, backgrounding or a profile reset must invalidate the pending landing.")
    }

    @MainActor
    func testObsoleteInitialHomeFocusCompletionCannotClearItsReplacement() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        let request = NTVInitialHeroFocusRequest(wait: {
            let count = await gate.started.count
            _ = try await gate.run("seed-\(count)")
        })
        var applied: [String] = []
        let old = request.schedule(router: router, hero: hero, isEligible: { true }) { applied.append("old") }
        try await until { await gate.started.count == 1 }
        let current = request.schedule(router: router, hero: hero, isEligible: { true }) { applied.append("current") }
        try await until { await gate.started.count == 2 }
        await gate.release("seed-0")
        await old.value
        XCTAssertTrue(applied.isEmpty)
        await gate.release("seed-1")
        await current.value
        XCTAssertEqual(applied, ["current"], "A cancelled task's cleanup must not discard its newer replacement.")
    }

    @MainActor
    func testInitialHomeFocusRechecksVisibilityBeforeApplying() async throws {
        let gate = Gate(), router = ContentFocusRouter(), hero = HeroFocus()
        let request = NTVInitialHeroFocusRequest(wait: { _ = try await gate.run("seed") })
        var eligible = true, applied = false
        let pending = request.schedule(router: router, hero: hero, isEligible: { eligible }) { applied = true }
        try await until { await gate.started.count == 1 }
        eligible = false
        await gate.release("seed")
        await pending.value
        XCTAssertFalse(applied, "A hidden or ineligible hero must not receive focus.")
    }

    func testFastFocusSweepCoalescesHeroWorkWithoutSlowingAnIsolatedStep() {
        var policy = NTVFocusSettlePolicy()
        XCTAssertEqual(policy.delay(at: 10, minimumNanoseconds: 60_000_000), 60_000_000)
        XCTAssertEqual(policy.delay(at: 10.08, minimumNanoseconds: 60_000_000), 300_000_000)
        XCTAssertEqual(policy.delay(at: 10.16, minimumNanoseconds: 60_000_000), 300_000_000)
        XCTAssertEqual(policy.delay(at: 10.60, minimumNanoseconds: 60_000_000), 60_000_000)
        XCTAssertEqual(policy.delay(at: 10.68, minimumNanoseconds: 220_000_000), 300_000_000)
        XCTAssertEqual(policy.delay(at: .nan, minimumNanoseconds: 60_000_000), 60_000_000)
        XCTAssertEqual(policy.delay(at: 9, minimumNanoseconds: 60_000_000), 60_000_000)
    }
    func testRemoteRepeatCadenceDoesNotCommitEveryIntermediateHero() {
        for interval in [0.15, 0.20, 0.28] {
            var policy = NTVFocusSettlePolicy()
            var pending: (id: Int, due: Double)?
            var committed: [Int] = []
            for step in 0..<8 {
                let now = Double(step) * interval
                if let pending, pending.due <= now { committed.append(pending.id) }
                let delay = policy.delay(at: now, minimumNanoseconds: 60_000_000)
                pending = (step, now + Double(delay) / 1_000_000_000)
            }
            if let pending { committed.append(pending.id) }
            XCTAssertEqual(committed, [0, 7], "Only the initial and settled title should start artwork/metadata work at \(interval)s repeats.")
        }
    }
    func testReleaseDateReusePreservesFractionsZonesAndUnknownDates() throws {
        let expected = Date(timeIntervalSince1970: 1_760_572_800)
        for _ in 0..<20 {
            XCTAssertEqual(ReleaseDateParser.parse("2025-10-16"), expected)
            XCTAssertEqual(ReleaseDateParser.parse("2025-10-16T02:00:00+02:00"), expected)
            XCTAssertEqual(ReleaseDateParser.parse("2025-10-16T00:00:00.250Z")?.timeIntervalSince1970 ?? 0,
                           expected.timeIntervalSince1970 + 0.25, accuracy: 0.001)
            XCTAssertNil(ReleaseDateParser.parse("unknown-date"))
        }
        XCTAssertEqual(ReleaseDateParser.parse("2025-10-16" + String(repeating: "x", count: 300)), expected,
                       "Long values must retain the existing ten-character date fallback without being cached.")
    }

    @MainActor
    func testCatalogIdentityAndAdjacentRowRoutingSurviveEmptyShelves() throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"routing-fixture","name":"Fixture","version":"1","types":["movie"],"resources":["catalog"],"catalogs":[{"id":"first","type":"movie"},{"id":"empty","type":"movie"},{"id":"last","type":"movie"}]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/catalog/manifest.json", manifest: manifest)
        let model = NTVCatalogBrowserModel()
        model.configure(addons: [addon], type: "movie", scope: "profile-one")
        XCTAssertEqual(model.sources.count, 3)
        let first = model.sources[0], middle = model.sources[1], last = model.sources[2]
        let rebuilt = NTVCatalogSource(addon: addon, catalog: first.catalog)
        XCTAssertEqual(rebuilt.id, first.id, "Recreating immutable source data must preserve poster/focus identity.")
        XCTAssertFalse(first.id.contains(addon.manifestURL), "Router identifiers must remain opaque.")
        model.noteVisibleStart(sourceID: middle.id, itemID: nil)
        XCTAssertEqual(model.adjacentNavigableSourceID(to: first.id, forward: true), last.id)
        XCTAssertEqual(model.adjacentNavigableSourceID(to: last.id, forward: false), first.id)
        XCTAssertNil(model.adjacentNavigableSourceID(to: first.id, forward: false))
        XCTAssertNil(model.adjacentNavigableSourceID(to: last.id, forward: true))
        model.noteVisibleStart(sourceID: middle.id, itemID: "now-visible")
        XCTAssertEqual(model.adjacentNavigableSourceID(to: first.id, forward: true), middle.id)
    }

    private actor AvailabilityProbe {
        var active = 0
        var maximum = 0
        var calls = 0
        func load() async throws -> [OrivioTV.Stream] {
            active += 1; maximum = max(maximum, active); calls += 1
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(30))
            return []
        }
        func snapshot() -> (Int, Int) { (maximum, calls) }
    }

    func testAvailabilityWindowBoundsActualProviderCallsAndSharesDuplicateTitles() async throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"fixture","name":"Fixture","version":"1","types":["movie"],"resources":["stream"]}"#.utf8))
        let addon = InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: manifest)
        let store = NTVSourceAvailabilityStore()
        let probe = AvailabilityProbe()
        try await withThrowingTaskGroup(of: NTVSourceAvailability.self) { group in
            for id in ["one", "two", "three", "four", "one"] {
                group.addTask {
                    try await store.check(item: MetaItem(id: id, type: "movie", name: "Fixture"), sources: [addon], scope: "fixture") { _, _, _ in
                        try await probe.load()
                    }
                }
            }
            for try await result in group { XCTAssertEqual(result, .absent) }
        }
        let (maximum, calls) = await probe.snapshot()
        XCTAssertEqual(maximum, 1, "Several rows must not fan out source searches concurrently.")
        XCTAssertEqual(calls, 4, "A duplicate title must reuse the same probe or its result.")
    }

    func testSharedAddonCancellationKeepsAnotherWaiterThenStopsActualHTTP() async throws {
        let probe = NTVBoundedHTTPProbe(stall: true)
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        let requests = RequestCoalescer(limit: 2)
        let first = Task {
            try await requests.data(for: "shared-addon") {
                try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 512).0
            }
        }
        try await until { probe.requestsReceived == 1 }
        let second = Task {
            try await requests.data(for: "shared-addon") {
                XCTFail("An identical addon request must share its HTTP transfer")
                return Data()
            }
        }
        try await until { await requests.activity.waiters == 2 }
        first.cancel()
        await expectCancellation(first)
        let remaining = await requests.activity
        XCTAssertEqual(remaining.waiters, 1)
        XCTAssertFalse(probe.isStopped, "Cancelling one screen must not stop another screen's transfer")
        XCTAssertEqual(probe.requestsReceived, 1)
        second.cancel()
        await expectCancellation(second)
        try await until { probe.isStopped }
        let ended = await requests.activity
        XCTAssertEqual(ended.waiters, 0)
    }

    func testAvailabilityTransferCannotImposeItsDeadlineOnManualSources() async throws {
        let probe = NTVBoundedHTTPProbe(stall: true)
        let (session, request) = NTVBoundedHTTPFixture.register(probe)
        defer { session.invalidateAndCancel(); NTVBoundedHTTPFixture.remove(probe.id) }
        let requests = RequestCoalescer(limit: 2)
        let url = try XCTUnwrap(request.url?.absoluteString)
        let probeRequest: URLRequest = { var value = request; value.timeoutInterval = 20; return value }()
        let sourcesRequest: URLRequest = { var value = request; value.timeoutInterval = 45; return value }()
        let availability = Task {
            try await requests.data(for: StremioAPI.coalescingKey(for: url, resource: .availabilityStreams)) {
                try await NTVBoundedResponse.data(for: probeRequest, session: session, maximumBytes: 512).0
            }
        }
        try await until { probe.requestsReceived == 1 }
        let sources = Task {
            try await requests.data(for: StremioAPI.coalescingKey(for: url, resource: .streams)) {
                try await NTVBoundedResponse.data(for: sourcesRequest, session: session, maximumBytes: 512).0
            }
        }
        try await until { probe.requestsReceived == 2 }
        availability.cancel(); await expectCancellation(availability)
        try await until { await requests.activity.running == 1 }
        let remaining = await requests.activity
        XCTAssertEqual(remaining.waiters, 1, "Leaving a poster must not cancel the manual Sources request.")
        XCTAssertEqual(remaining.running, 1, "Sources retains its independent transfer and deadline.")
        XCTAssertEqual(probe.requestsReceived, 2, "The shorter background deadline must not be inherited through shared HTTP.")
        sources.cancel(); await expectCancellation(sources)
        try await until { await requests.activity.running == 0 }
    }

    @MainActor
    func testActualSearchModelBoundsCallsAndPreservesProviderOrder() async throws {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(#"{"id":"ntv-search-fixture","name":"Fixture","version":"1","resources":["meta","catalog"],"types":["movie"],"catalogs":[{"id":"search","type":"movie","extraSupported":["search"],"extraRequired":["search"]}]}"#.utf8))
        let manager = AddonManager(startRefresh: false, manifestLoader: { _ in manifest })
        let prefix = "https://example.invalid/search-\(UUID())/"
        for index in 0..<6 { try await manager.install(manifestURL: prefix + "\(index)/manifest.json") }
        defer { for addon in manager.addons where addon.manifestURL.hasPrefix(prefix) { manager.remove(addon) } }
        let targets = SearchViewModel.searchTargets(manager)
        let gate = Gate()
        let model = SearchViewModel(requestLimit: 2, debounce: .zero) { addon, catalog, _ in
            let key = ImageCache.artworkKey("\(addon.id)#\(catalog.type)#\(catalog.id)", budget: nil)
            _ = try await gate.run(key)
            return [MetaItem(id: "shared", type: "movie", name: "Shared"),
                    MetaItem(id: key, type: "movie", name: "Provider"),
                    MetaItem(id: key, type: "movie", name: "Duplicate")]
        }
        model.query = "film"
        model.search(addonManager: manager)
        try await until { await gate.started.count >= 2 }
        let initial = await gate.started
        XCTAssertEqual(initial.count, 2, "The real search model must not launch all addon catalogs at once")
        var released = Set<String>()
        for count in stride(from: 2, through: targets.count + 1, by: 2) {
            try await until { await gate.started.count >= min(count, targets.count) }
            let started = await gate.started
            for key in started.reversed() where released.insert(key).inserted { await gate.release(key) }
        }
        try await until { await MainActor.run { !model.isSearching } }
        XCTAssertEqual(model.results.map(\.id), ["shared"] + targets.map { ImageCache.artworkKey("\($0.0.id)#\($0.1.type)#\($0.1.id)", budget: nil) },
                       "Out-of-order responses must preserve provider ranking and deduplication")
        let starts = await gate.started
        model.suspendSearch()
        model.resumeSearchIfNeeded(addonManager: manager)
        try await Task.sleep(for: .milliseconds(50))
        let afterReturn = await gate.started
        XCTAssertEqual(afterReturn, starts, "A completed search remains reusable when returning to its tab")
    }

    func testHomeCacheKeepsTheLatestSubmittedSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ntv-home-cache-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("catalogs.json")
        let older = (0..<30_000).map { MetaItem(id: String($0), type: "movie", name: "Older") }
        let latest = [MetaItem(id: "latest", type: "movie", name: "Latest")]
        HomeCatalogCache.save(["older": older], to: file)
        HomeCatalogCache.save(["latest": latest], to: file)
        await HomeCatalogCache.waitForPendingWrites()
        let restored = HomeCatalogCache.load(from: file)
        XCTAssertEqual(Set(restored.keys), ["latest"])
        XCTAssertEqual(restored["latest"], latest, "An older expensive encode cannot overwrite a newer snapshot")
    }

    @MainActor
    func testRapidBackdropUpdatesCommitOnlyTheFinalSelection() async throws {
        let canvas = NTVBackdropCanvas(settleDelay: .milliseconds(40))
        canvas.activate("films")
        canvas.update("films", url: "https://example.invalid/initial.jpg")
        var updates: [String?] = []
        let observer = canvas.$url.dropFirst().sink { updates.append($0) }
        for index in 0..<30 { canvas.update("films", url: "https://example.invalid/\(index).jpg") }
        XCTAssertEqual(canvas.url, "https://example.invalid/initial.jpg")
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(updates, ["https://example.invalid/29.jpg"], "Fast browsing must not launch thirty full-screen image replacements.")
        withExtendedLifetime(observer) {}
    }
    @MainActor
    func testReturningToDisplayedBackdropCancelsThePendingOtherTitle() async throws {
        let canvas = NTVBackdropCanvas(settleDelay: .milliseconds(40))
        canvas.activate("films")
        canvas.update("films", url: "https://example.invalid/x.jpg")
        canvas.update("films", url: "https://example.invalid/y.jpg")
        canvas.update("films", url: "https://example.invalid/x.jpg")
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(canvas.url, "https://example.invalid/x.jpg")
    }
    @MainActor
    func testLeavingASectionCancelsItsPendingBackdropWithoutLeakingAcrossProfiles() async throws {
        let canvas = NTVBackdropCanvas(settleDelay: .milliseconds(40))
        canvas.activate("films")
        canvas.update("films", url: "https://example.invalid/initial.jpg")
        canvas.update("films", url: "https://example.invalid/pending.jpg")
        canvas.update("series", url: "https://example.invalid/series.jpg")
        canvas.activate("series")
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(canvas.url, "https://example.invalid/series.jpg")
        canvas.update("series", url: "https://example.invalid/late.jpg")
        canvas.clear()
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertNil(canvas.url)
    }
    @MainActor
    func testNormalPosterDecodeKeepsFocusHeadroomWithoutAnOversizedBitmap() async throws {
        let height: CGFloat = 330
        let budget = try XCTUnwrap(RemoteImage.pixelBudget(maxDimension: height, maxPixels: nil))
        XCTAssertGreaterThanOrEqual(budget, height * UIScreen.main.scale * 1.1,
                                    "The focused poster must retain sufficient display resolution.")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
        }
        let data = try XCTUnwrap(original.pngData())
        let image = try await ImageCache.shared.preparedImage(data, budget: budget, memoryKey: UUID().uuidString)
        let bitmap = try XCTUnwrap(image?.cgImage)
        XCTAssertLessThanOrEqual(bitmap.height, 960)
        XCTAssertLessThan(bitmap.bytesPerRow * bitmap.height, 4_000_000,
                          "A small catalog poster must not occupy a full 5 MB rendition in normal mode.")
    }
    private actor Gate {
        private(set) var started: [String] = []
        private var held: [String: CheckedContinuation<Int, Error>] = [:]
        func mark(_ key: String) { started.append(key) }
        func run(_ key: String) async throws -> Int {
            started.append(key)
            return try await withCheckedThrowingContinuation { held[key] = $0 }
        }
        func release(_ key: String, value: Int = 1) { held.removeValue(forKey: key)?.resume(returning: value) }
        func fail(_ key: String) { held.removeValue(forKey: key)?.resume(throwing: FixtureFailure.failed) }
    }
    private enum FixtureFailure: Error { case failed, timeout }

    private func until(_ condition: () async -> Bool) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()) {
            guard clock.now < deadline else { throw FixtureFailure.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    private func expectCancellation<T: Sendable>(_ task: Task<T, Error>) async {
        do { _ = try await task.value; XCTFail("Cancelled waiter returned a value") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation result") }
    }

    func testSharedWindowBoundsActualWorkAcrossDifferentKeys() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 2), gate = Gate()
        let tasks = (0..<6).map { index in
            Task { try await pool.value(for: String(index)) { try await gate.run(String(index)) } }
        }
        try await until { await pool.activity.waiters == 6 }
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 2)
        XCTAssertEqual(activity.queued, 4)
        for batch in 0..<3 {
            try await until { await gate.started.count == (batch + 1) * 2 }
            let keys = await gate.started
            for key in keys.suffix(2) { await gate.release(key) }
        }
        for task in tasks { let value = try await task.value; XCTAssertEqual(value, 1) }
        let ended = await pool.activity
        XCTAssertEqual(ended.running, 0)
        XCTAssertEqual(ended.queued, 0)
        XCTAssertEqual(ended.waiters, 0)
    }

    func testEarlyDeliveryKeepsItsSlotAndSharesItsValueUntilFollowUpFinishes() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let ready = expectation(description: "Value delivered while follow-up is held")
        let shared = expectation(description: "Late consumer shares the early value")
        let first = Task {
            let value = try await pool.valueBeforeFinishing(for: "artwork") { deliver in
                await deliver(7)
                _ = try await gate.run("persist")
                return 7
            }
            ready.fulfill(); return value
        }
        try await until { await gate.started.count == 1 }
        await fulfillment(of: [ready], timeout: 3)
        let late = Task {
            let value = try await pool.value(for: "artwork") { XCTFail("Duplicated in-flight artwork"); return 99 }
            shared.fulfill(); return value
        }
        await fulfillment(of: [shared], timeout: 3)
        let next = Task { try await pool.value(for: "next") { await gate.mark("next"); return 8 } }
        try await until { await pool.activity.queued == 1 }
        let held = await pool.activity
        XCTAssertEqual(held.running, 1, "Persistence continues to own the bounded work slot.")
        XCTAssertEqual(held.waiters, 1, "The displayed image is no longer an awaiting UI consumer.")
        let starts = await gate.started
        XCTAssertEqual(starts, ["persist"])
        await gate.release("persist")
        let firstValue = try await first.value, lateValue = try await late.value
        XCTAssertEqual(firstValue, 7); XCTAssertEqual(lateValue, 7)
        let nextValue = try await next.value
        XCTAssertEqual(nextValue, 8)
        try await until { await pool.activity.running == 0 }
    }

    func testEarlyDeliveryCanShareAnOptionalNilWithoutStartingDuplicateWork() async throws {
        let pool = NTVSharedWorkPool<Int?>(limit: 1), gate = Gate()
        let ready = expectation(description: "Optional nil delivered before completion")
        let shared = expectation(description: "Optional nil shared with late consumer")
        let first = Task {
            let value = try await pool.valueBeforeFinishing(for: "optional") { deliver in
                await deliver(nil)
                _ = try await gate.run("finish")
                return nil
            }
            ready.fulfill(); return value
        }
        try await until { await gate.started.count == 1 }
        await fulfillment(of: [ready], timeout: 3)
        let late = Task {
            let value = try await pool.value(for: "optional") { XCTFail("A delivered nil is still a delivered value"); return 42 }
            shared.fulfill(); return value
        }
        await fulfillment(of: [shared], timeout: 3)
        await gate.release("finish")
        let firstValue = try await first.value, lateValue = try await late.value
        XCTAssertNil(firstValue); XCTAssertNil(lateValue)
        try await until { await pool.activity.running == 0 }
    }

    func testCancelledEarlyProducerCannotDeliverIntoItsReplacement() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let old = Task {
            try await pool.valueBeforeFinishing(for: "same") { deliver in
                let value = try await gate.run("old") // deliberately ignores cancellation
                await deliver(value)
                return value
            }
        }
        try await until { await gate.started.count == 1 }
        old.cancel(); await expectCancellation(old)
        let current = Task { try await pool.value(for: "same") { try await gate.run("current") } }
        try await until { await pool.activity.queued == 1 }
        await gate.release("old", value: 100)
        try await until { await gate.started.count == 2 }
        await gate.release("current", value: 200)
        let value = try await current.value
        XCTAssertEqual(value, 200)
    }

    func testFailedFollowUpReleasesItsSlotWithoutRetractingTheDeliveredValue() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let ready = expectation(description: "Ready value delivered before follow-up failure")
        let task = Task {
            let value = try await pool.valueBeforeFinishing(for: "artwork") { deliver in
                await deliver(3)
                _ = try await gate.run("persist")
                throw FixtureFailure.failed
            }
            ready.fulfill(); return value
        }
        try await until { await gate.started.count == 1 }
        await fulfillment(of: [ready], timeout: 3)
        await gate.release("persist")
        let value = try await task.value
        XCTAssertEqual(value, 3)
        try await until { await pool.activity.running == 0 }
        let retry = try await pool.value(for: "artwork") { 4 }
        XCTAssertEqual(retry, 4)
    }

    func testConcurrentConsumersShareOneOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 4), gate = Gate()
        let first = Task { try await pool.value(for: "poster") { try await gate.run("poster") } }
        try await until { await gate.started.count == 1 }
        let second = Task { try await pool.value(for: "poster") { XCTFail("Duplicate work started"); return 99 } }
        try await until { await pool.activity.waiters == 2 }
        await gate.release("poster", value: 7)
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a, 7); XCTAssertEqual(b, 7)
        let starts = await gate.started
        XCTAssertEqual(starts, ["poster"])
    }

    func testCancellingOneConsumerKeepsSharedWorkForTheOther() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let first = Task { try await pool.value(for: "poster") { try await gate.run("poster") } }
        try await until { await gate.started.count == 1 }
        let second = Task { try await pool.value(for: "poster") { XCTFail("Duplicate work started"); return 99 } }
        try await until { await pool.activity.waiters == 2 }
        first.cancel()
        await expectCancellation(first)
        let remaining = await pool.activity
        XCTAssertEqual(remaining.waiters, 1)
        await gate.release("poster", value: 8)
        let result = try await second.value
        XCTAssertEqual(result, 8)
    }

    func testQueuedCancellationNeverStartsTheAbandonedOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let held = Task { try await pool.value(for: "held") { try await gate.run("held") } }
        try await until { await gate.started.count == 1 }
        let abandoned = Task { try await pool.value(for: "abandoned") { XCTFail("Cancelled queued work started"); return 99 } }
        try await until { await pool.activity.queued == 1 }
        abandoned.cancel(); await expectCancellation(abandoned)
        await gate.release("held")
        _ = try await held.value
        let activity = await pool.activity
        XCTAssertEqual(activity.queued, 0)
        let starts = await gate.started
        XCTAssertEqual(starts, ["held"])
    }

    func testLastCancellationKeepsSlotUntilOldWorkStopsAndCannotPoisonReplacement() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        // This gate deliberately ignores cancellation, like an ImageIO call
        // already decoding. Releasing its waiter must not free its work slot.
        let old = Task { try await pool.value(for: "same-key") { try await gate.run("old") } }
        try await until { await gate.started.count == 1 }
        old.cancel(); await expectCancellation(old)
        let replacement = Task { try await pool.value(for: "same-key") { try await gate.run("new") } }
        try await until { await pool.activity.queued == 1 }
        let held = await pool.activity
        XCTAssertEqual(held.running, 1)
        let starts = await gate.started
        XCTAssertEqual(starts, ["old"])
        await gate.release("old", value: 100)
        try await until { await gate.started.count == 2 }
        await gate.release("new", value: 200)
        let result = try await replacement.value
        XCTAssertEqual(result, 200, "The old generation cannot deliver its result to a replacement.")
    }

    func testAlreadyCancelledConsumerDoesNotEnqueueWork() async {
        let pool = NTVSharedWorkPool<Int>(limit: 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pool.value(for: "unused") { XCTFail("Pre-cancelled work started"); return 1 }
        }
        await expectCancellation(task)
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 0)
        XCTAssertEqual(activity.waiters, 0)
    }

    func testLastWaiterCancellationReachesTheUnderlyingOperation() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let task = Task {
            try await pool.value(for: "transfer") {
                await gate.mark("transfer")
                try await Task.sleep(for: .seconds(30))
                return 99
            }
        }
        try await until { await gate.started.count == 1 }
        task.cancel(); await expectCancellation(task)
        try await until { await pool.activity.running == 0 }
        let activity = await pool.activity
        XCTAssertEqual(activity.waiters, 0, "Cancelling the last waiter must also stop cancellable underlying work.")
    }

    func testFailedSharedWorkReleasesItsSlotAndCanBeRetried() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let first = Task { try await pool.value(for: "key") { try await gate.run("first") } }
        try await until { await gate.started.count == 1 }
        await gate.fail("first")
        do { _ = try await first.value; XCTFail("Expected failure") } catch is FixtureFailure {}
        let retry = try await pool.value(for: "key") { 42 }
        XCTAssertEqual(retry, 42)
        let activity = await pool.activity
        XCTAssertEqual(activity.running, 0)
    }

    func testVisibleConsumerOvertakesQueuedPrefetchAndPromotesSharedKey() async throws {
        let pool = NTVSharedWorkPool<Int>(limit: 1), gate = Gate()
        let held = Task { try await pool.value(for: "held") { try await gate.run("held") } }
        try await until { await gate.started.count == 1 }
        let background = Task { try await pool.value(for: "background", priority: .background) { try await gate.run("background") } }
        try await until { await pool.activity.queued == 1 }
        let promoted = Task { try await pool.value(for: "promoted", priority: .background) { try await gate.run("promoted") } }
        try await until { await pool.activity.queued == 2 }
        let visible = Task { try await pool.value(for: "promoted") { XCTFail("Promotion duplicated work"); return 99 } }
        try await until { await pool.activity.waiters == 4 }
        await gate.release("held"); _ = try await held.value
        try await until { await gate.started.count == 2 }
        let starts = await gate.started
        XCTAssertEqual(starts, ["held", "promoted"])
        await gate.release("promoted", value: 10)
        _ = try await promoted.value; let visibleResult = try await visible.value
        XCTAssertEqual(visibleResult, 10)
        try await until { await gate.started.count == 3 }
        await gate.release("background"); _ = try await background.value
    }

    func testCancelledAddonSweepDoesNotStartItsRemainingItems() async throws {
        let gate = Gate()
        let task = Task {
            await boundedConcurrentMap(Array(0..<100), limit: 2) { index in
                (try? await gate.run(String(index))) ?? -1
            }
        }
        try await until { await gate.started.count == 2 }
        task.cancel()
        await gate.release("0"); await gate.release("1")
        let values = await task.value
        XCTAssertTrue(values.isEmpty, "A cancelled sweep cannot publish a partial array with shifted indices.")
        let starts = await gate.started
        XCTAssertEqual(starts.count, 2, "No refill of a cancelled sweep.")
    }

    func testAlreadyCancelledSweepStartsNothing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await boundedConcurrentMap([1, 2, 3], limit: 2) { _ in XCTFail("Cancelled sweep started"); return 1 }
        }
        let values = await task.value
        XCTAssertTrue(values.isEmpty)
    }

    func testBoundedSweepPreservesOrderWhenCompletionOrderDiffers() async throws {
        let gate = Gate()
        let task = Task {
            await boundedConcurrentMap([0, 1, 2], limit: 3) { index in
                (try? await gate.run(String(index))) ?? -1
            }
        }
        try await until { await gate.started.count == 3 }
        for index in [2, 0, 1] { await gate.release(String(index), value: index * 10) }
        let values = await task.value
        XCTAssertEqual(values, [0, 10, 20])
    }

    @MainActor
    private func jpeg(width: Int = 2048, height: Int = 1024, orientation: Int = 1) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testArtworkDecodeRespectsPixelBudgetAndOrientation() async throws {
        let data = try await jpeg(orientation: 6)
        let image = try XCTUnwrap(ImageCache.decodeDownsampled(data, budget: 340))
        XCTAssertEqual(image.cgImage?.width, 170)
        XCTAssertEqual(image.cgImage?.height, 340)
        XCTAssertEqual(image.imageOrientation, .up)
    }

    func testArtworkDecodeRejectsInvalidBytesAndInvalidBudgets() async throws {
        XCTAssertNil(ImageCache.decodeDownsampled(Data("invalid image".utf8), budget: 340))
        let data = try await jpeg(width: 24, height: 12)
        XCTAssertNil(ImageCache.decodeDownsampled(data, budget: 0))
        XCTAssertNil(ImageCache.decodeDownsampled(data, budget: -1))
        let small = try XCTUnwrap(ImageCache.decodeDownsampled(data, budget: 128))
        XCTAssertEqual(small.cgImage?.width, 24, "A bounded decode must not enlarge a small original.")
    }

    @MainActor
    func testArtworkBucketsNeverExceedExplicitHardCap() {
        XCTAssertEqual(RemoteImage.pixelBudget(maxDimension: nil, maxPixels: 2560), 2560)
        XCTAssertEqual(RemoteImage.pixelBudget(maxDimension: 5000, maxPixels: 512), 512)
        XCTAssertLessThanOrEqual(RemoteImage.pixelBudget(maxDimension: 300, maxPixels: 512) ?? 9999, 512)
    }

    func testConcurrentArtworkPreparationReusesTheSameDecodedObject() async throws {
        let data = try await jpeg(), key = "ntv-fixture-\(UUID())#340"
        async let a = ImageCache.shared.preparedImage(data, budget: 340, memoryKey: key)
        async let b = ImageCache.shared.preparedImage(data, budget: 340, memoryKey: key)
        let (first, second) = try await (a, b)
        let image = try XCTUnwrap(first), reused = try XCTUnwrap(second)
        XCTAssertTrue(image === reused, "Two views must share a single prepared rendition.")
        XCTAssertEqual(image.cgImage?.width, 340)
    }

    func testArtworkPreparationKeepsSmallAndLargeRenditionsSeparate() async throws {
        let data = try await jpeg(), key = "ntv-fixture-\(UUID())"
        let small = try await ImageCache.shared.preparedImage(data, budget: 240, memoryKey: key + "#240")
        let large = try await ImageCache.shared.preparedImage(data, budget: 680, memoryKey: key + "#680")
        XCTAssertEqual(small?.cgImage?.width, 240)
        XCTAssertEqual(large?.cgImage?.width, 680)
        XCTAssertFalse(small === large)
    }
}
