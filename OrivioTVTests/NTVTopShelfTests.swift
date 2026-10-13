import XCTest
import TVServices

final class NTVTopShelfTests: XCTestCase {
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
