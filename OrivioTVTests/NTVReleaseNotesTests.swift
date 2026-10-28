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

    func testResumeAndPresentationShareTheUnacknowledgedBuildPolicy() {
        let notes = NTVReleaseNotes.current
        let defaults = UserDefaults(suiteName: "NTVReleaseNotesTests.\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey: NTVReleaseNotes.seenBuildKey) }
        func due(_ arguments: [String] = []) -> Bool {
            notes.shouldPresent(installedBuild: notes.build,
                seenBuild: defaults.string(forKey: NTVReleaseNotes.seenBuildKey) ?? "", arguments: arguments)
        }
        XCTAssertTrue(due(), "An early queued resume must wait even before the notes cover mounts.")
        #if DEBUG
        XCTAssertFalse(due(["-homeDemo"]))
        XCTAssertFalse(due(["-ntvLaunchTest"]))
        XCTAssertTrue(due(["-homeDemo", "-ntvReleaseNotesDemo"]))
        #endif
        defaults.set(notes.build, forKey: NTVReleaseNotes.seenBuildKey)
        XCTAssertFalse(due(), "Acknowledging the version releases the pending resume.")
    }
}
