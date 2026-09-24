import XCTest
@testable import ClipHackKit

/// Where a test run's preferences go: never `UserDefaults.standard`, and never
/// a file left behind in ~/Library/Preferences.
@MainActor
final class SettingsStoreTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try ScratchDefaults.install()
    }

    override func tearDown() {
        ScratchDefaults.uninstall()
        super.tearDown()
    }

    /// A test that forgets ScratchDefaults still gets a scratch store.
    func testATestRunDoesNotDefaultToTheStandardDefaults() {
        XCTAssertFalse(UserDefaults.app === UserDefaults.standard)
    }

    /// The suite lives in a temporary folder of its own, and uninstall deletes
    /// the folder rather than only emptying the suite.
    func testScratchDefaultsDeletesItsFolderAndRestoresTheDefault() throws {
        let folder = try XCTUnwrap(ScratchDefaults.folder)
        XCTAssertTrue(folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))

        let settings = ClipHackSettings(outputDirectoryPath: "/tmp/scratch-output")
        settings.save()
        XCTAssertEqual(ClipHackSettings.load().outputDirectoryPath, "/tmp/scratch-output")

        ScratchDefaults.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(ClipHackSettings.store === UserDefaults.app)
    }
}
