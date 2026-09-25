import XCTest
@testable import ClipHackKit

/// Redirects ClipHack's persisted preferences to a throwaway suite.
///
/// `ContentViewModel.settings` saves on every change, so any test that
/// constructs a view model and touches a setting writes to whatever
/// `ClipHackSettings.store` points at — which is how a test run could quietly
/// repoint the user's download and output folders. Install this in `setUp` for
/// any test class that touches settings, presets, or the view model, and
/// uninstall it in `tearDown`.
@MainActor
enum ScratchDefaults {
    /// The installed suite's folder; nil when nothing is installed.
    ///
    /// A fresh folder per install, with the suite named by a path inside it,
    /// and `uninstall` deletes the folder. The suite used to be named like a
    /// bundle id — io.github.sevmorris.ClipHack.tests.<pid> — and a suite named
    /// that way lives in ~/Library/Preferences: removing its domain empties the
    /// file but leaves it there, and deleting the file does not hold either,
    /// because cfprefsd writes it back. By 2026-09-24 there were 27 of them,
    /// matching the io.github.sevmorris.* pattern Magic Backup Machine's App
    /// Preferences source backs up. Deleting a folder of our own does hold. A
    /// folder per install also keeps xcodebuild's parallel test processes out
    /// of each other's settings.
    private(set) static var folder: URL?
    private static var suite: UserDefaults?
    private static var suiteName = ""

    /// Throws, failing the test, if the suite cannot be made. There is no
    /// fallback store: any other is one a test has no business writing to.
    static func install() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-defaults-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        suiteName = folder.appendingPathComponent("defaults").path
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        self.suite = suite
        ClipHackSettings.store = suite
    }

    static func uninstall() {
        suite?.removePersistentDomain(forName: suiteName)
        suite = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        ClipHackSettings.store = .app
    }
}
