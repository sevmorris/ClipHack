import Foundation

/// One episode's working folder.
///
/// A session is a folder, not a record: its name *is* the title, so there is
/// nothing to keep in sync when a folder is renamed or moved, one made in
/// Finder shows up on its own, and the name travels with the files.
///
///     ~/Desktop/Hacks on Tap/          ← root, one per show
///     └── HT_0379 2026-08-24/          ← the session; its name is the title
///         └── clips/                   ← where downloads are filed
///             └── Some Title/
///                 ├── Some Title.m4a
///                 └── Some Title.txt
struct ClipSession: Identifiable, Equatable, Sendable {
    /// The episode folder. Its last path component is the session title.
    let folder: URL
    /// Where clips are actually filed — the `clips` subfolder when there is
    /// one, otherwise the episode folder itself.
    let clipsFolder: URL

    var title: String { folder.lastPathComponent }
    var id: URL { folder }
}

enum ClipSessionStore {

    /// Subfolder downloads are filed into inside an episode folder.
    static let clipsSubfolder = "clips"

    /// Default episode prefix. One show, so one prefix.
    static let defaultPrefix = "HT"

    // MARK: - Reading

    /// Every episode folder under `root`, newest first.
    ///
    /// Sorted by name descending with a natural-order compare, which puts
    /// `HT_0380` above `HT_0379` whether or not the numbers are zero-padded.
    static func sessions(inRoot root: URL) -> [ClipSession] {
        directories(in: root)
            .map { ClipSession(folder: $0, clipsFolder: clipsFolder(for: $0)) }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedDescending
            }
    }

    /// Where clips go inside an episode folder: `clips` when that folder
    /// exists, else the episode folder itself — so a session made by hand
    /// without the subfolder still works.
    static func clipsFolder(for episodeFolder: URL) -> URL {
        let nested = episodeFolder.appendingPathComponent(clipsSubfolder, isDirectory: true)
        return isDirectory(nested) ? nested : episodeFolder
    }

    /// The session a download folder belongs to, read back from the path.
    ///
    /// A folder named `clips` is the nested case, so its parent is the episode;
    /// anything else is treated as the episode folder itself.
    static func session(forClipsFolder folder: URL) -> ClipSession {
        let standardized = folder.standardizedFileURL
        if standardized.lastPathComponent == clipsSubfolder {
            return ClipSession(
                folder: standardized.deletingLastPathComponent(),
                clipsFolder: standardized
            )
        }
        return ClipSession(folder: standardized, clipsFolder: standardized)
    }

    /// The show root a download folder implies — the episode folder's parent.
    /// Used to adopt a root the first time without asking for one.
    static func inferredRoot(forClipsFolder folder: URL) -> URL {
        session(forClipsFolder: folder).folder.deletingLastPathComponent()
    }

    // MARK: - Naming

    /// The number and zero-padding for the next episode under `root`.
    ///
    /// Padding follows the highest episode already there, so a show numbering
    /// `HT_0379` keeps four digits and one numbering `HT_12` keeps two.
    static func nextEpisodeNumber(inRoot root: URL, prefix: String = defaultPrefix) -> (number: Int, width: Int) {
        var highest = 0
        var width = 0
        for folder in directories(in: root) {
            guard let digits = episodeDigits(folder.lastPathComponent, prefix: prefix),
                  let value = Int(digits) else { continue }
            if value >= highest {
                highest = value
                width = digits.count
            }
        }
        return (highest + 1, max(width, 1))
    }

    /// The suggested title for a new session: the next episode number and
    /// today's date, in the shape the folders already use.
    static func nextTitle(
        inRoot root: URL,
        prefix: String = defaultPrefix,
        date: Date
    ) -> String {
        let next = nextEpisodeNumber(inRoot: root, prefix: prefix)
        let number = String(format: "%0\(next.width)d", next.number)
        return "\(prefix)_\(number) \(dateString(date))"
    }

    /// `yyyy-MM-dd`, fixed-format so it does not follow the user's locale.
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The digits following `<prefix>_` at the start of a folder name, or nil
    /// when the name is not an episode of this show.
    static func episodeDigits(_ name: String, prefix: String = defaultPrefix) -> String? {
        let head = prefix + "_"
        guard name.hasPrefix(head) else { return nil }
        let digits = name.dropFirst(head.count).prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    // MARK: - Writing

    /// Creates `<root>/<title>/clips` and returns the session.
    ///
    /// Creating the clips subfolder up front is what makes the layout
    /// consistent — a session made here never falls back to the flat form.
    @discardableResult
    static func create(title: String, inRoot root: URL) throws -> ClipSession {
        let folder = root.appendingPathComponent(title, isDirectory: true)
        let clips = folder.appendingPathComponent(clipsSubfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        return ClipSession(folder: folder, clipsFolder: clips)
    }

    // MARK: - Private

    private static func directories(in url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter(isDirectory)
    }

    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
