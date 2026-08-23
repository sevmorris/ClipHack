import Foundation
@testable import ClipHackKit

/// Redirects ClipHack's persisted preferences to a throwaway suite.
///
/// `ContentViewModel.settings` saves on every change, so any test that
/// constructs a view model and touches a setting writes to the real user's
/// defaults — which is how a test run could quietly repoint their download and
/// output folders. Install this in `setUp` for any test class that touches
/// settings, presets, or the view model.
@MainActor
enum ScratchDefaults {
    /// One fixed suite, not a fresh UUID per install: `setUp` runs once per
    /// test *method*, so a unique name each time leaves a stray plist per test
    /// in ~/Library/Preferences. Cleared on the way in as well as out, so a
    /// test still starts from empty defaults.
    private static let suiteName = "io.github.sevmorris.ClipHack.tests"

    static func install() {
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        suite.removePersistentDomain(forName: suiteName)
        ClipHackSettings.store = suite
    }

    static func uninstall() {
        ClipHackSettings.store.removePersistentDomain(forName: suiteName)
        ClipHackSettings.store = .standard
    }
}
