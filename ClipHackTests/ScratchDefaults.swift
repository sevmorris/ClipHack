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
    /// One suite per test *process*.
    ///
    /// Not a fresh name per install — `setUp` runs once per test method, and a
    /// unique name each time leaves a stray plist per test behind. Not one
    /// fixed name either: xcodebuild runs test classes in parallel processes,
    /// and a shared suite means one class's teardown wipes another's settings
    /// mid-test. Keyed on the pid, both problems go away — a handful of files,
    /// each owned by exactly one process.
    private static let suiteName =
        "io.github.sevmorris.ClipHack.tests.\(ProcessInfo.processInfo.processIdentifier)"

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
