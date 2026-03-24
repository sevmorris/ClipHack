import SwiftUI

@main
struct ClipHackApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await checkForUpdates(silent: true)
                }
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
