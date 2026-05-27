import Foundation

enum OutputDirectory {
    nonisolated static func clipHackOutputDirectory(
        for input: URL,
        settings: ClipHackSettings,
        onWarning: ((String) -> Void)? = nil
    ) -> URL {
        let fm = FileManager.default

        if let customPath = settings.outputDirectoryPath {
            let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
            if fm.isWritableFile(atPath: customURL.path) { return customURL }
            onWarning?("Custom output directory not writable (\(customPath)), falling back.")
        }

        let here = input.deletingLastPathComponent()
        if fm.isWritableFile(atPath: here.path) { return here }

        onWarning?("Source directory not writable, falling back to ~/Music/ClipHack.")
        let music = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/ClipHack", isDirectory: true)
        if (try? fm.createDirectory(at: music, withIntermediateDirectories: true)) != nil,
           fm.isWritableFile(atPath: music.path) {
            return music
        }

        onWarning?("~/Music/ClipHack unavailable, falling back to Desktop.")
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
