import XCTest
@testable import OrivioTV

final class NTVReleaseNotesTests: XCTestCase {
    func testOnlyAnUnseenInstalledReleaseIsPresented() {
        let notes = NTVReleaseNotes.current
        XCTAssertTrue(notes.shouldPresent(installedBuild: notes.build, seenBuild: "49"))
        XCTAssertTrue(notes.shouldPresent(installedBuild: notes.build, seenBuild: ""))
        XCTAssertFalse(notes.shouldPresent(installedBuild: notes.build, seenBuild: notes.build))
        XCTAssertFalse(notes.shouldPresent(installedBuild: "49", seenBuild: ""))
        XCTAssertFalse(notes.shouldPresent(installedBuild: "", seenBuild: ""))
    }

    func testReleaseContentMatchesTheShippingBuildAndHasTestingGuidance() {
        let notes = NTVReleaseNotes.current
        XCTAssertEqual(notes.build, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertFalse(notes.improvements.isEmpty)
        XCTAssertFalse(notes.checks.isEmpty)
        XCTAssertEqual(Set(notes.improvements).count, notes.improvements.count)
        XCTAssertEqual(Set(notes.checks).count, notes.checks.count)
    }
}
