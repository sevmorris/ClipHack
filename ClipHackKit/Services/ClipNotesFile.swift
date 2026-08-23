import Foundation

/// The plain-text notes sidecar that sits beside a downloaded clip inside its
/// own folder — `Title/Title.m4a` next to `Title/Title.txt`.
///
/// Replaces the daily `clip-list-YYYY-MM-DD.txt` this app used to append to, but
/// deliberately keeps that file's body verbatim: filename / notes (a blank line
/// when empty) / source URL, then a trailing blank line. Concatenating the
/// sidecars (`cat */*.txt`) therefore reproduces a clip list exactly, so
/// WireHack's logs and anything else reading that format still work.
enum ClipNotesFile {
    /// Sidecar name for an audio file: same stem, `.txt`.
    static func filename(forAudioFile audioFilename: String) -> String {
        let stem = (audioFilename as NSString).deletingPathExtension
        return (stem.isEmpty ? audioFilename : stem) + ".txt"
    }

    /// Empty notes are written as a blank line so the four-line shape holds
    /// whether or not notes were entered; multiline notes are kept verbatim
    /// (the trailing blank line still delimits one clip from the next).
    static func body(filename: String, notes: String, sourceURL: String) -> String {
        "\(filename)\n\(notes)\n\(sourceURL)\n\n"
    }

    /// Writes the sidecar next to `audioFile`. One clip per file, so this
    /// overwrites rather than appends — a re-download of the same clip records
    /// the notes it was downloaded with, not a growing history.
    static func write(notes: String, sourceURL: String, forAudioFile audioFile: URL) throws {
        let url = audioFile
            .deletingLastPathComponent()
            .appendingPathComponent(filename(forAudioFile: audioFile.lastPathComponent))
        let text = body(
            filename: audioFile.lastPathComponent,
            notes: notes,
            sourceURL: sourceURL
        )
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// What a sidecar records. `filename` is the name the clip had when it was
    /// downloaded — a later rename doesn't rewrite it, so treat it as a hint
    /// rather than the truth about what's on disk now.
    struct Record: Equatable {
        var filename: String
        var notes: String
        var sourceURL: String
    }

    /// Parses a sidecar body. The inverse of `body(filename:notes:sourceURL:)`:
    /// first line is the filename, last non-empty line is the source URL, and
    /// everything between is the notes — which may run to any number of lines,
    /// blank ones included.
    static func parse(_ text: String) -> Record? {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard lines.count >= 2 else { return nil }

        let sourceURL = lines.removeLast()
        let filename = lines.removeFirst()
        guard !filename.isEmpty, !sourceURL.isEmpty else { return nil }
        return Record(
            filename: filename,
            notes: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL
        )
    }

    /// Reads the sidecar sitting beside `audioFile`, if there is one. Silent on
    /// every failure — restoring notes is a convenience, never a blocker.
    static func read(forAudioFile audioFile: URL) -> Record? {
        let url = audioFile
            .deletingLastPathComponent()
            .appendingPathComponent(filename(forAudioFile: audioFile.lastPathComponent))
        return readSidecar(at: url)
    }

    static func readSidecar(at url: URL) -> Record? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// True when two source URLs point at the same clip. Exact match, plus X
    /// post URLs compared by status ID so the same post pasted with different
    /// tracking params still matches. Deliberately does NOT ignore query
    /// strings in general — for YouTube and friends the video id lives there.
    static func isSameSource(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if a == b { return !a.isEmpty }
        if let idA = XPostText.statusID(from: a), let idB = XPostText.statusID(from: b) {
            return idA == idB
        }
        return false
    }

    /// Finds a clip already downloaded from `sourceURL`, by reading the notes
    /// sidecars in `directory` and its clip folders (one level down — that is
    /// exactly where downloads are filed). Returns the audio file itself.
    ///
    /// The audio has to still be on disk: sidecars outlive the clips they
    /// describe when a show's files are deleted, and a leftover note must never
    /// block re-downloading.
    static func existingClip(forSourceURL sourceURL: String, in directory: URL) -> URL? {
        for sidecar in sidecarURLs(in: directory) {
            guard let record = readSidecar(at: sidecar),
                  isSameSource(record.sourceURL, sourceURL),
                  let audio = audioFile(for: record, sidecar: sidecar) else { continue }
            return audio
        }
        return nil
    }

    /// One row per clip sidecar under `directory` — for a per-episode download
    /// folder, that is exactly this show's clips. Ordered by when each sidecar
    /// was written, so the list reads back in the order clips were added over
    /// the week rather than alphabetically.
    ///
    /// `audio` is nil when the clip's audio is gone. Sidecars outlive the files
    /// they describe, and that is the point: a list has to survive a cleanup.
    struct Entry: Equatable, Identifiable {
        var sidecar: URL
        var record: Record
        var audio: URL?

        var id: URL { sidecar }
    }

    static func entries(in directory: URL) -> [Entry] {
        let found: [(entry: Entry, added: Date)] = sidecarURLs(in: directory).compactMap { url in
            guard let record = readSidecar(at: url) else { return nil }
            let added = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                ?? Date.distantPast
            let entry = Entry(
                sidecar: url,
                record: record,
                audio: audioFile(for: record, sidecar: url)
            )
            return (entry, added)
        }
        return found.sorted { lhs, rhs in
            guard lhs.added == rhs.added else { return lhs.added < rhs.added }
            return lhs.entry.sidecar.lastPathComponent
                .localizedStandardCompare(rhs.entry.sidecar.lastPathComponent) == .orderedAscending
        }.map(\.entry)
    }

    /// Rewrites just the notes of an existing sidecar, keeping the filename and
    /// source URL it already recorded. This is the write path for editing a
    /// clip's list entry after the download that created it — the recorded
    /// filename stays a snapshot of download time, exactly as `write` leaves it.
    static func updateNotes(_ notes: String, atSidecar sidecar: URL) throws {
        guard let record = readSidecar(at: sidecar) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let text = body(filename: record.filename, notes: notes, sourceURL: record.sourceURL)
        try Data(text.utf8).write(to: sidecar, options: .atomic)
    }

    /// Sidecars in `directory` and in each of its immediate subfolders.
    private static func sidecarURLs(in directory: URL) -> [URL] {
        let folders = [directory] + contents(of: directory).filter(isDirectory)
        return folders.flatMap { folder in
            contents(of: folder).filter { $0.pathExtension.lowercased() == "txt" }
        }
    }

    /// The audio file a sidecar describes: the name it recorded, or — when that
    /// has been renamed away — a same-stem sibling next to the sidecar.
    private static func audioFile(for record: ClipNotesFile.Record, sidecar: URL) -> URL? {
        let folder = sidecar.deletingLastPathComponent()
        let recorded = folder.appendingPathComponent(record.filename)
        if FileManager.default.fileExists(atPath: recorded.path) { return recorded }

        let stem = sidecar.deletingPathExtension().lastPathComponent
        return contents(of: folder).first {
            $0.pathExtension.lowercased() != "txt"
                && $0.deletingPathExtension().lastPathComponent == stem
        }
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    // nonisolated so it can be passed to filter as a method reference — the
    // project's MainActor default isolation would otherwise apply here.
    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
