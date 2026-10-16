import Foundation

/// One episode's working folder.
///
/// A session is a folder, not a record: its name *is* the title, so there is
/// nothing to keep in sync when a folder is renamed or moved, and the name
/// travels with the files. ClipHack makes none of them — the show's weekly
/// prep does — and works in the newest (`ClipSessionStore.newestEpisode`).
///
///     ~/Desktop/Example Show/          ← root, one per show
///     └── HT_0379 2026-08-24/          ← the session; its name is the title
///         └── clips/                   ← where downloads land
///             ├── Some Title.m4a
///             └── HT_0379 2026-08-24.txt
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

    /// The highest-numbered episode under `root`, or nil when there is none.
    ///
    /// The show's weekly prep makes the next episode and clears the last one
    /// out, so this is the one being worked on — the same rule the show's own
    /// tools use to find it.
    static func newestEpisode(inRoot root: URL) -> ClipSession? {
        sessions(inRoot: root).first { episodeDigits($0.title) != nil }
    }

    /// Every folder under `root` as a session, episodes first and newest first.
    ///
    /// A show folder holds more than episodes — templates, shared assets,
    /// incoming audio — and a plain name sort buries the episodes under them.
    /// Numbered episodes are ordered by their number, highest first, and
    /// everything else follows in reading order so it stays reachable without
    /// being in the way.
    static func sessions(inRoot root: URL) -> [ClipSession] {
        directories(in: root)
            .map { ClipSession(folder: $0, clipsFolder: clipsFolder(for: $0)) }
            .sorted { lhs, rhs in
                let left = episodeDigits(lhs.title).flatMap(Int.init)
                let right = episodeDigits(rhs.title).flatMap(Int.init)
                switch (left, right) {
                case let (l?, r?):
                    return l > r
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    /// Where clips go inside an episode folder: `clips` when that folder
    /// exists, else the episode folder itself — so a session made by hand
    /// without the subfolder still works.
    static func clipsFolder(for episodeFolder: URL) -> URL {
        let nested = episodeFolder.appendingPathComponent(clipsSubfolder, isDirectory: true)
        return isDirectory(nested) ? nested : episodeFolder
    }

    /// Where `session` files clips as the disk stands now: its `clips` folder
    /// when one exists at this moment, otherwise the folder it was read with.
    ///
    /// A session is read when the menu's list is, and an episode folder made
    /// in the Finder usually gets its `clips` folder after that — a session
    /// read in between names the episode folder itself. The correction runs
    /// one way only: a session that already names a `clips` folder since
    /// removed keeps it, so the missing folder is reported where it is used
    /// rather than quietly swapped for the episode folder above it.
    static func currentClipsFolder(for session: ClipSession) -> URL {
        let nested = session.folder.appendingPathComponent(clipsSubfolder, isDirectory: true)
        return isDirectory(nested) ? nested : session.clipsFolder
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

    /// Normalizes a folder chosen as the show root.
    ///
    /// Picking the *episode* instead of the show above it is an easy mistake —
    /// the session menu then lists `ads`, `clips` and `recordings` as if each
    /// were an episode. A chosen folder is treated as an episode when it is
    /// named like one, or when it holds a `clips` folder; the show is then its
    /// parent. Picking the `clips` folder itself goes up two.
    static func normalizedRoot(_ chosen: URL) -> URL {
        let name = chosen.lastPathComponent
        if name == clipsSubfolder {
            return chosen.deletingLastPathComponent().deletingLastPathComponent()
        }
        if episodeDigits(name) != nil {
            return chosen.deletingLastPathComponent()
        }
        if isDirectory(chosen.appendingPathComponent(clipsSubfolder, isDirectory: true)) {
            return chosen.deletingLastPathComponent()
        }
        return chosen
    }

    // MARK: - Naming

    /// The digits following `<prefix>_` at the start of a folder name, or nil
    /// when the name is not an episode of this show.
    static func episodeDigits(_ name: String, prefix: String = defaultPrefix) -> String? {
        let head = prefix + "_"
        guard name.hasPrefix(head) else { return nil }
        let digits = name.dropFirst(head.count).prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
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
