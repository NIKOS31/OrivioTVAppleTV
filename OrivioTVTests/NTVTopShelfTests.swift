import XCTest
import TVServices
@testable import OrivioTV

final class NTVTopShelfTests: XCTestCase {
    private let callback: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLName": "tv.orivio.callback", "CFBundleURLSchemes": ["orivio"]]]]

    func testContinuationHasPostersProgressAndLocalResumeActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "topshelf-artwork-" + String(repeating: "a", count: 64) + ".jpg"
        let artwork = directory.appendingPathComponent(name)
        try Data([0]).write(to: artwork)
        let snapshot = NTVTopShelfSnapshot(version: 1, writtenAt: Date(), profileID: 1, entries: [
            .init(id: "tt1234567", type: "series", title: "Série", subtitle: "S2:E3", imageFileName: name, progress: 0.45)
        ])
        let content = try XCTUnwrap(TopShelfProvider.continuationContent(snapshot, containingAppInfo: callback,
            artworkDirectory: directory, fallbackImage: directory.appendingPathComponent("brand.png")))
        let section = try XCTUnwrap(content.sections.first)
        XCTAssertEqual(section.title, "Continuer à regarder")
        let item = try XCTUnwrap(section.items.first)
        XCTAssertEqual(item.title, "Série · S2:E3")
        XCTAssertEqual(item.imageShape, .poster)
        XCTAssertEqual(item.playbackProgress, 0.45)
        XCTAssertEqual(item.imageURL(for: .screenScale1x), artwork)
        XCTAssertEqual(item.imageURL(for: .screenScale2x), artwork)
        XCTAssertEqual(DeepLinkService.parse(try XCTUnwrap(item.playAction?.url)), .resume(type: "series", id: "tt1234567"))
        XCTAssertEqual(DeepLinkService.parse(try XCTUnwrap(item.displayAction?.url)), .meta(type: "series", id: "tt1234567"))
    }

    func testContinuationRejectsTraversalDuplicateAndInvalidTypes() throws {
        let directory = URL(fileURLWithPath: "/fixture")
        let fallback = directory.appendingPathComponent("brand.png")
        let entry = NTVTopShelfSnapshot.Entry(id: "tt1", type: "movie", title: "Film", subtitle: nil,
            imageFileName: "../../secret.jpg", progress: 3)
        let bad = NTVTopShelfSnapshot.Entry(id: "x", type: "unsupported", title: "Bad", subtitle: nil, imageFileName: nil, progress: nil)
        let snapshot = NTVTopShelfSnapshot(version: 1, writtenAt: Date(), profileID: 1, entries: [entry, entry, bad])
        let content = try XCTUnwrap(TopShelfProvider.continuationContent(snapshot, containingAppInfo: callback,
            artworkDirectory: directory, fallbackImage: fallback))
        let items = try XCTUnwrap(content.sections.first).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.imageURL(for: .screenScale1x), fallback)
        XCTAssertEqual(items.first?.playbackProgress, 1)
        XCTAssertNil(TopShelfProvider.continuationContent(snapshot, containingAppInfo: nil, artworkDirectory: directory, fallbackImage: fallback))
    }

    func testSnapshotRejectsStaleFutureOversizedAndExcessiveEntries() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let item = NTVTopShelfSnapshot.Entry(id: "tt1", type: "movie", title: "Film", subtitle: nil, imageFileName: nil, progress: 0.2)
        func data(_ date: Date, count: Int = 1, version: Int = 1) throws -> Data {
            try JSONEncoder().encode(NTVTopShelfSnapshot(version: version, writtenAt: date, profileID: 1,
                entries: Array(repeating: item, count: count)))
        }
        XCTAssertNotNil(NTVTopShelfSnapshot.decode(try data(now), now: now))
        XCTAssertNil(NTVTopShelfSnapshot.decode(try data(now.addingTimeInterval(-7 * 86400)), now: now))
        XCTAssertNil(NTVTopShelfSnapshot.decode(try data(now.addingTimeInterval(61)), now: now))
        XCTAssertNil(NTVTopShelfSnapshot.decode(try data(now, count: 11), now: now))
        XCTAssertNil(NTVTopShelfSnapshot.decode(try data(now, version: 2), now: now))
        XCTAssertNil(NTVTopShelfSnapshot.decode(Data(repeating: 0, count: NTVTopShelfSnapshot.maximumBytes + 1), now: now))
        XCTAssertFalse(NTVTopShelfSnapshot.safeArtworkName("../../secret.jpg"))
        XCTAssertFalse(NTVTopShelfSnapshot.safeArtworkName("https://example.invalid/poster.jpg"))
    }

    func testSnapshotContainsNoPlaybackSourceOrAddonURL() throws {
        let progress = WatchProgress(id: "tt1", metaID: "tt1", type: "movie", name: "Film",
            poster: "https://example.invalid/private-poster", background: nil, logo: nil, season: nil, episode: nil,
            episodeTitle: nil, positionSeconds: 20, durationSeconds: 100,
            streamURL: "https://example.invalid/private-stream", updatedAt: Date())
        let input = try XCTUnwrap(TopShelfExporter.entries(from: [progress]).first)
        XCTAssertEqual(input.progress, 0.2)
        let safe = NTVTopShelfSnapshot.Entry(id: input.id, type: input.type, title: input.title,
            subtitle: input.subtitle, imageFileName: nil, progress: input.progress)
        let bytes = try JSONEncoder().encode(NTVTopShelfSnapshot(version: 1, writtenAt: Date(), profileID: 1, entries: [safe]))
        let json = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(json.contains("private-stream"))
        XCTAssertFalse(json.contains("private-poster"))
        XCTAssertFalse(json.contains("imageURL"))
        XCTAssertFalse(json.contains("streamURL"))
    }

    func testBrandImageCanBeRetrievedForEitherDeviceScale() throws {
        let image = URL(fileURLWithPath: "/fixture/ntv.png")
        let content = TopShelfProvider.brandedContent(image: image, containingAppInfo: [
            "CFBundleIdentifier": "test.ntv.SIGNEDTEAM",
            "CFBundleURLTypes": [["CFBundleURLName": "tv.orivio.callback", "CFBundleURLSchemes": ["test.ntv"]]]
        ])
        let item = try XCTUnwrap(content.items.first)
        XCTAssertEqual(item.imageURL(for: .screenScale1x), image)
        XCTAssertEqual(item.imageURL(for: .screenScale2x), image)
        XCTAssertEqual(item.displayAction?.url.absoluteString, "test.ntv://home")
        XCTAssertEqual(content.items.count, 1)
    }

    func testBrandDoesNotInventACallbackForAnUnrelatedBundle() throws {
        let content = TopShelfProvider.brandedContent(image: URL(fileURLWithPath: "/fixture/ntv.png"), containingAppInfo: nil)
        XCTAssertNil(try XCTUnwrap(content.items.first).displayAction)
    }

    func testBrandRejectsUnregisteredOrMalformedCallbackSchemes() throws {
        let image = URL(fileURLWithPath: "/fixture/ntv.png")
        let configurations: [[[String: Any]]] = [
            [["CFBundleURLName": "unrelated", "CFBundleURLSchemes": ["test.ntv"]]],
            [["CFBundleURLName": "tv.orivio.callback", "CFBundleURLSchemes": ["test.ntv://unexpected"]]],
            [["CFBundleURLName": "tv.orivio.callback", "CFBundleURLSchemes": [] as [String]]]
        ]
        for types in configurations {
            let content = TopShelfProvider.brandedContent(image: image, containingAppInfo: ["CFBundleURLTypes": types])
            XCTAssertNil(try XCTUnwrap(content.items.first).displayAction)
        }
    }
}
