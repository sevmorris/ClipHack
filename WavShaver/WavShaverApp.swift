import SwiftUI

@main
struct ClipHackerApp: App {
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
                Button("ClipHacker Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)

                Divider()

                Button("Check for Updates…") {
                    Task { await checkForUpdates(silent: false) }
                }
            }
        }

        Window("ClipHacker Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
