import SwiftUI

@main
struct ClipHackApp: App {
    @Environment(\.openWindow) private var openWindow

    init() {
        Task { await checkForUpdates(silent: true) }
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
