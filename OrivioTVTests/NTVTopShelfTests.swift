import XCTest
import TVServices

final class NTVTopShelfTests: XCTestCase {
    func testBrandImageCanBeRetrievedForEitherDeviceScale() throws {
        let image = URL(fileURLWithPath: "/fixture/ntv.png")
        let content = TopShelfProvider.brandedContent(image: image, identifier: "test.ntv.topshelf")
        let item = try XCTUnwrap(content.items.first)
        XCTAssertEqual(item.imageURL(for: .screenScale1x), image)
        XCTAssertEqual(item.imageURL(for: .screenScale2x), image)
        XCTAssertEqual(item.displayAction?.url.absoluteString, "test.ntv://home")
        XCTAssertEqual(content.items.count, 1)
    }

    func testBrandDoesNotInventACallbackForAnUnrelatedBundle() throws {
        let content = TopShelfProvider.brandedContent(image: URL(fileURLWithPath: "/fixture/ntv.png"), identifier: "unrelated")
        XCTAssertNil(try XCTUnwrap(content.items.first).displayAction)
    }
}
