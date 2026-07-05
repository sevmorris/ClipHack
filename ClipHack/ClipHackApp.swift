import SwiftUI

@main
struct ClipHackApp: App {
    @Environment(\.openWindow) private var openWindow

    /// True when the process is hosting an XCTest run. The unit tests use this
    /// app as their XCTest host; firing the launch-time network update check in
    /// that process makes `xcodebuild test` hang launching the host before any
    /// test runs (observed on CI and locally).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    init() {
        if !Self.isRunningTests {
            Task { await checkForUpdates(silent: true) }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("ClipHack Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)

                Divider()

                Button("Check for Updates…") {
                    Task { await checkForUpdates(silent: false) }
                }
            }
        }

        Window("ClipHack Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
