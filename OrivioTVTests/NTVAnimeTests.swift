import XCTest
@testable import OrivioTV

final class NTVAnimeTests: XCTestCase {
    private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Paris")!
        return value
    }
    private func media(_ id: Int = 1, adult: String = "false", image: String = "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/test.jpg") -> String {
        "{\"id\":\(id),\"title\":{\"romaji\":\"Animé de test\"},\"isAdult\":\(adult),\"coverImage\":{\"large\":\"\(image)\"}}"
    }
    func testCalendarDaysUseRealLocalMidnightsThroughBothDSTChanges() {
        let calendar = calendar()
        for (month, expectedHours) in [(3, 23.0), (10, 25.0)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 29 : 25, hour: 12))!
            let days = NTVAnimeDay.week(containing: date, calendar: calendar)
            XCTAssertEqual(days.count, 7)
            XCTAssertEqual(calendar.component(.weekday, from: days[0].start), 2)
            let current = days.first { $0.contains(date) }!
            XCTAssertEqual(current.end.timeIntervalSince(current.start) / 3600, expectedHours)
            XCTAssertTrue(current.contains(current.start))
            XCTAssertFalse(current.contains(current.end))
            for index in 1..<days.count { XCTAssertEqual(days[index - 1].end, days[index].start) }
        }
    }
    func testSeasonBoundaryDoesNotDependOnElapsedDaySeconds() {
        let calendar = calendar()
        for (month, season) in [(1, "WINTER"), (4, "SPRING"), (7, "SUMMER"), (10, "FALL")] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: 1))!
            XCTAssertEqual(NTVAnimeRequest.season(at: date, calendar: calendar), .season(year: 2026, name: season))
        }
    }
    func testSeasonRejectsAdultOrUnspecifiedRatingAndDeduplicatesMedia() throws {
        let json = "{\"data\":{\"Page\":{\"media\":[\(media()),\(media()),\(media(2, adult: "true")),\(media(3, adult: "null"))]}}}"
        let feed = try NTVAnimeService.decode(Data(json.utf8), for: .season(year: 2026, name: "FALL"))
        XCTAssertEqual(feed.entries.map(\.media.id), [1])
    }
    func testScheduleKeepsOnlyTheSelectedHalfOpenDayAndSortsAirings() throws {
        let request = NTVAnimeRequest.day(start: 100_000, end: 186_400)
        func airing(_ id: Int, _ time: Int) -> String {
            "{\"id\":\(id),\"episode\":2,\"airingAt\":\(time),\"media\":\(media())}"
        }
        let json = "{\"data\":{\"Page\":{\"pageInfo\":{\"hasNextPage\":true},\"airingSchedules\":[\(airing(1, 186_399)),\(airing(2, 100_000)),\(airing(3, 186_400)),\(airing(4, 99_999)),\(airing(2, 100_000))]}}}"
        let feed = try NTVAnimeService.decode(Data(json.utf8), for: request)
        XCTAssertEqual(feed.entries.map(\.id), ["airing.2", "airing.1"])
        XCTAssertTrue(feed.hasMore)
    }
    func testGraphQLErrorsAndOversizedOrExcessivePagesAreNotPresentedAsEmptySuccess() throws {
        let request = NTVAnimeRequest.season(year: 2026, name: "FALL")
        XCTAssertThrowsError(try NTVAnimeService.decode(Data("{\"data\":{\"Page\":{\"media\":[]}},\"errors\":[{\"message\":\"private remote error\"}]}".utf8), for: request))
        XCTAssertThrowsError(try NTVAnimeService.decode(Data(repeating: 32, count: (1 << 20) + 1), for: request))
        let many = (1...25).map { media($0) }.joined(separator: ",")
        XCTAssertThrowsError(try NTVAnimeService.decode(Data("{\"data\":{\"Page\":{\"media\":[\(many)]}}}".utf8), for: request))
    }
    func testArtworkCannotUseLocalHostsCredentialsOrNonHTTPS() throws {
        for image in ["http://s4.anilist.co/file/anilistcdn/media/a.jpg", "https://127.0.0.1/file/anilistcdn/media/a.jpg", "https://secret@s4.anilist.co/file/anilistcdn/media/a.jpg", "file:///private/a.jpg", "https://s4.anilist.co/file/anilistcdn/media/a.jpg?redirect=http://127.0.0.1"] {
            let item = try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(media(image: image).utf8))
            XCTAssertNil(item.artwork)
        }
        XCTAssertNotNil(try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(media().utf8)).artwork)
    }
    func testCalendarQueryUsesBoundedVariablesAndDoesNotEmbedSearchText() throws {
        let data = try NTVAnimeService.payload(for: .day(start: 100_000, end: 186_400))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let variables = try XCTUnwrap(payload["variables"] as? [String: Int])
        XCTAssertEqual(variables["from"], 99_999)
        XCTAssertEqual(variables["to"], 186_400)
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .day(start: 20, end: 10)))
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .day(start: 20, end: Int.max)))
        XCTAssertThrowsError(try NTVAnimeService.payload(for: .season(year: 2026, name: "FALL) { other }")))
    }
    func testRateLimitStopsSubsequentRequestsWithoutExposingResponseBody() async throws {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let client = NTVAnimeService { request in
            await counter.increment()
            XCTAssertEqual(request.url?.absoluteString, "https://graphql.anilist.co")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "nan"])!
            return (Data("untrusted body".utf8), response)
        }
        for _ in 0..<2 {
            do { _ = try await client.load(.season(year: 2026, name: "FALL")); XCTFail("Expected backoff") }
            catch { XCTAssertEqual(error as? NTVAnimeError, .limited) }
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testSummaryRemainsBoundedPlainTextInsteadOfHTML() throws {
        let json = "{\"id\":1,\"title\":{\"romaji\":\"Test\"},\"description\":\"<i>Un titre</i><br><br/>Texte &amp; suite\",\"isAdult\":false}"
        let item = try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(json.utf8))
        XCTAssertFalse(item.summary.contains("<"))
        XCTAssertTrue(item.summary.contains("Texte & suite"))
        XCTAssertTrue(item.summary.contains("\n"))
        let long = "{\"id\":1,\"title\":{\"romaji\":\"Test\"},\"description\":\"" + String(repeating: "a", count: 8000) + "\"}"
        XCTAssertEqual(try JSONDecoder().decode(NTVAnimeMedia.self, from: Data(long.utf8)).summary.count, 2000)
    }

    func testPublicMetadataIsReusedWithoutSendingAnAccountOrAddon() async throws {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        let body = Data("{\"data\":{\"Page\":{\"media\":[]}}}".utf8)
        let client = NTVAnimeService { request in
            await counter.increment()
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (body, response)
        }
        let request = NTVAnimeRequest.season(year: 2026, name: "FALL")
        _ = try await client.load(request)
        _ = try await client.load(request)
        let count = await counter.count
        XCTAssertEqual(count, 1, "Returning to the same season must use its short-lived cache.")
    }
}
