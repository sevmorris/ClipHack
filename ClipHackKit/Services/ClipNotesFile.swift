import Foundation

/// The plain-text notes sidecar that sat beside a downloaded clip inside the
/// per-clip folder ClipHack used to make — `Title/Title.m4a` next to
/// `Title/Title.txt`.
///
/// One blank-line-separated block per element, in this order:
///
///     Some Title.m4a          ← omitted when the clip was named by hand
///
///     TRUMP — "the quote"     ← who and what, then any scratch
///
///     1:13 to :55             ← the cut, when one was entered
///
///     https://x.com/…
///
/// The filename is dropped for a hand-named clip because it then says nothing
/// the name did not already say. Nothing needs it to find the audio: the
/// sidecar shares the clip's stem, which is what `audioFile(for:sidecar:)`
/// falls back to.
///
/// **The app no longer writes these.** A session keeps one file holding every
/// clip (`SessionNotesFile`), and each block in it is exactly the body defined
/// here — so this type is now the block format plus the reader that folds
/// pre-existing per-clip files into a session. `write` remains as the authoring
/// side of that legacy shape.
enum ClipNotesFile {
    /// Sidecar name for an audio file: same stem, `.txt`.
    static func filename(forAudioFile audioFilename: String) -> String {
        let stem = (audioFilename as NSString).deletingPathExtension
        return (stem.isEmpty ? audioFilename : stem) + ".txt"
    }

    /// Assembles the sidecar body. Empty elements are left out entirely rather
    /// than written as blank lines, so the blank line between blocks always
    /// means "next element" and never "this one was empty".
    static func body(
        filename: String,
        notes: String,
        timestamp: String = "",
        sourceURL: String
    ) -> String {
        let blocks = [filename, notes, timestamp, sourceURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Writes the sidecar next to `audioFile`. One clip per file, so this
    /// overwrites rather than appends — a re-download of the same clip records
    /// the notes it was downloaded with, not a growing history.
    ///
    /// `includeFilename` is false for a clip the user named themselves: the
    /// line would only repeat the name they just typed.
    static func write(
        notes: String,
        timestamp: String = "",
        sourceURL: String,
        forAudioFile audioFile: URL,
        includeFilename: Bool = true
    ) throws {
        let url = audioFile
            .deletingLastPathComponent()
            .appendingPathComponent(filename(forAudioFile: audioFile.lastPathComponent))
        let text = body(
            filename: includeFilename ? audioFile.lastPathComponent : "",
            notes: notes,
            timestamp: timestamp,
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
        /// The cut, e.g. "1:13 to :55". Empty when none was entered.
        var timestamp: String = ""
        var sourceURL: String
    }

    /// Audio extensions a first line has to end in to read as a filename rather
    /// than as the start of the notes.
    private static let audioExtensions: Set<String> = [
        "wav", "aif", "aiff", "mp3", "flac", "m4a", "ogg", "opus", "caf", "wma",
        "aac", "mp4", "mov",
    ]

    /// True when a line is an in/out timestamp rather than prose — "1:13 to :55",
    /// ":30 to :12", "To :17", "0:05".
    ///
    /// A colon is required, so a stray number at the end of the notes is not
    /// mistaken for a cut. Only ever applied to the last block before the URL,
    /// which is where `body` puts one.
    static func isTimestamp(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains("\n") else { return false }
        let pattern = #"^(?:to\s+)?\d{0,2}:\d{1,2}(?:\s*(?:to|-|–|—|>)\s*\d{0,2}:?\d{1,2})?$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parses a sidecar body — the inverse of `body`.
    ///
    /// Read from the ends inward, because that is what stays stable when the
    /// optional elements come and go: the last non-empty line is always the
    /// source URL, a first line ending in an audio extension is the filename,
    /// the last block above the URL is the timestamp when it reads as one, and
    /// whatever remains is the notes.
    ///
    /// Reads the pre-1.22 shape too, where the elements were single lines with
    /// no blank between them and a cut lived at the end of the notes — such a
    /// file comes back with its timestamp lifted into its own field.
    static func parse(_ text: String) -> Record? {
        var lines = text.components(separatedBy: "\n")
        func dropTrailingBlanks() {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
        }
        func dropLeadingBlanks() {
            while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeFirst()
            }
        }

        dropTrailingBlanks()
        guard !lines.isEmpty else { return nil }

        let sourceURL = lines.removeLast().trimmingCharacters(in: .whitespaces)
        guard !sourceURL.isEmpty else { return nil }
        // A lone line is only a record if it is actually a source URL; without
        // this any one-line text file in a clip folder would read as a clip.
        guard !lines.isEmpty || sourceURL.contains("://") else { return nil }

        dropTrailingBlanks()
        dropLeadingBlanks()

        var filename = ""
        if let first = lines.first {
            let candidate = first.trimmingCharacters(in: .whitespaces)
            if audioExtensions.contains((candidate as NSString).pathExtension.lowercased()) {
                filename = candidate
                lines.removeFirst()
                dropLeadingBlanks()
            }
        }

        var timestamp = ""
        if let start = lastBlockStart(in: lines) {
            let block = lines[start...].joined(separator: "\n")
            if isTimestamp(block) {
                timestamp = block.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.removeSubrange(start...)
                dropTrailingBlanks()
            }
        }

        return Record(
            filename: filename,
            notes: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: timestamp,
            sourceURL: sourceURL
        )
    }

    /// Index of the first line of the final blank-line-separated block.
    private static func lastBlockStart(in lines: [String]) -> Int? {
        guard !lines.isEmpty else { return nil }
        var index = lines.count - 1
        while index > 0, !lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            index -= 1
        }
        return index
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
        // Guard the empty case: appending "" lands back on the folder, which
        // exists, so a hand-named clip would report its own folder as the audio.
        if !record.filename.isEmpty {
            let recorded = folder.appendingPathComponent(record.filename)
            if FileManager.default.fileExists(atPath: recorded.path) { return recorded }
        }

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
