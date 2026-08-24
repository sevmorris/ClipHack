import Foundation

/// One notes file per session, holding every clip in it.
///
///     HT_0379 2026-08-24/clips/HT_0379 2026-08-24.txt
///
/// Blocks are separated by a `---` rule; each block is exactly the body
/// `ClipNotesFile` already defines, so the element rules — blank line between
/// elements, filename only when ClipHack chose it, cut on its own line — are
/// shared rather than duplicated.
///
///     Aaron_Rupar_-_TRUMP_….m4a
///
///     TRUMP — "I should be at 100 percent on the economy"
///
///     :46 to :17
///
///     https://x.com/atrupar/status/2090948085333504072
///
///     ---
///
///     MAMDANI — I continue to support Congressman Jeffries
///     …
///
/// Maintained, never appended. ClipHack rewrites the file from what it holds,
/// so a re-download or an edit replaces a clip's block instead of stacking a
/// second one after it. That is the whole reason the per-clip files replaced
/// the daily appending log this returns to: an append-only file grows a history
/// and then has to be pruned by hand.
enum SessionNotesFile {

    /// Rule between clips. A line of its own, so a block can contain anything.
    static let separator = "---"

    /// The session's notes file, named after the session itself.
    static func url(inClipsFolder folder: URL, title: String) -> URL {
        folder.appendingPathComponent("\(title).txt")
    }

    // MARK: - Rendering

    static func render(_ records: [ClipNotesFile.Record]) -> String {
        records
            .map {
                ClipNotesFile.body(
                    filename: $0.filename,
                    notes: $0.notes,
                    timestamp: $0.timestamp,
                    sourceURL: $0.sourceURL
                )
            }
            .joined(separator: "\n\(separator)\n\n")
    }

    static func parse(_ text: String) -> [ClipNotesFile.Record] {
        text
            .components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces) == separator })
            .map { $0.joined(separator: "\n") }
            .compactMap(ClipNotesFile.parse)
    }

    // MARK: - Disk

    static func read(at url: URL) -> [ClipNotesFile.Record] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func write(_ records: [ClipNotesFile.Record], to url: URL) throws {
        guard !records.isEmpty else {
            // An emptied session leaves no stale file behind.
            try? FileManager.default.removeItem(at: url)
            return
        }
        try Data(render(records).utf8).write(to: url, options: .atomic)
    }

    /// Replaces the block for `record`'s source, or appends it when the clip is
    /// new. This is the download path — the panel rewrites the whole file.
    static func upsert(_ record: ClipNotesFile.Record, at url: URL) throws {
        var records = read(at: url)
        if let index = records.firstIndex(where: {
            ClipNotesFile.isSameSource($0.sourceURL, record.sourceURL)
        }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try write(records, to: url)
    }

    // MARK: - Migration

    /// Folds any per-clip sidecars under `folder` into the session file, in the
    /// order they were written, and reports how many were taken in.
    ///
    /// The originals are deliberately left on disk: they are the user's files,
    /// and a migration that deletes them has no undo. They are simply no longer
    /// read. Clips already present in the session file are not duplicated.
    @discardableResult
    static func adoptSidecars(in folder: URL, sessionFile: URL) throws -> Int {
        let existing = read(at: sessionFile)
        let strays = ClipNotesFile.entries(in: folder)
            .filter { $0.sidecar.standardizedFileURL.path != sessionFile.standardizedFileURL.path }
            .map(\.record)
            .filter { stray in
                !existing.contains { ClipNotesFile.isSameSource($0.sourceURL, stray.sourceURL) }
            }
        guard !strays.isEmpty else { return 0 }
        try write(existing + strays, to: sessionFile)
        return strays.count
    }
}
