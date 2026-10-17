import Foundation

/// The session's record of its clips, for ClipHack's own use: each download's
/// file name, cut and link, and the cut of any clip added from disk.
///
///     HT_0385 2026-10-13/clips/HT_0385 2026-10-13.txt
///
///     CSPAN_-_President_Trump_….m4a
///         https://x.com/cspan/status/2109039198422405195
///
///     This_Week_-_Kansas_Senate 1.23 to .52.m4a
///         CUT  1:23 to :52
///         https://x.com/thisweekabc/status/2109318964635730038
///
/// Two things read it. A link pasted again is matched against the recorded
/// links, so the clip is added back, or asked about, instead of fetched twice.
/// A clip added back to the list gets its cut from its block, so Change Cut…
/// knows which cut to take off its name. Nobody reads the file by hand,
/// and the show's clip skill leaves it alone, so it is read only as ClipHack
/// writes it: a name flush left starts a block, and the indented `CUT` and
/// link lines under it are its cut and source.
///
/// Maintained, never appended. ClipHack rewrites the file from what it holds,
/// so a re-download or an edit replaces a clip's block instead of stacking a
/// second one after it.
///
/// `nonisolated`: pure text and file handling.
nonisolated enum SessionNotesFile {

    /// Marks a clip's cut, so it stands out from the link under it.
    static let cutLabel = "CUT"

    /// Every line of a block after its file name.
    private static let indent = "    "

    /// The session's notes file, named after the session itself.
    static func url(inClipsFolder folder: URL, title: String) -> URL {
        folder.appendingPathComponent("\(title).txt")
    }

    // MARK: - Rendering

    /// The whole file: the clips' blocks, a blank line between each.
    static func render(_ records: [ClipRecord]) -> String {
        records.map { block(for: $0).joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    private static func block(for record: ClipRecord) -> [String] {
        var lines = [trimmed(record.filename)]
        let cut = trimmed(record.timestamp)
        if !cut.isEmpty { lines.append("\(indent)\(cutLabel)  \(cut)") }
        let source = tidied(record.sourceURL)
        if !source.isEmpty { lines.append(indent + source) }
        return lines
    }

    /// An X post's link without its tracking query (`?s=43`). The post id is in
    /// the path, and `ClipRecord.isSameSource` matches X links by that id.
    /// Every other link stays exactly as recorded: a YouTube video's id lives
    /// in its query.
    static func tidied(_ link: String) -> String {
        let link = trimmed(link)
        guard XPostLink.statusID(from: link) != nil,
              var parts = URLComponents(string: link)
        else { return link }
        parts.query = nil
        parts.fragment = nil
        return parts.string ?? link
    }

    // MARK: - Parsing

    /// The blocks `render` writes. A line flush left is the next clip's name;
    /// under it, `CUT  <cut>` is its cut and a link is its source. Anything
    /// else is skipped.
    static func parse(_ text: String) -> [ClipRecord] {
        var records: [ClipRecord] = []
        for raw in text.components(separatedBy: "\n") {
            let line = trimmed(raw)
            guard !line.isEmpty else { continue }
            if raw.first != " " && raw.first != "\t" {
                records.append(ClipRecord(filename: line))
            } else if !records.isEmpty {
                if let cut = cutValue(line) {
                    records[records.count - 1].timestamp = cut
                } else if line.contains("://") && !line.contains(" ") {
                    records[records.count - 1].sourceURL = line
                }
            }
        }
        return records
    }

    /// "CUT  1:23 to :52" → "1:23 to :52"; nil for any other line.
    private static func cutValue(_ line: String) -> String? {
        let head = cutLabel + " "
        guard line.hasPrefix(head) else { return nil }
        let value = trimmed(String(line.dropFirst(head.count)))
        return value.isEmpty ? nil : value
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Disk

    static func read(at url: URL) -> [ClipRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func write(_ records: [ClipRecord], to url: URL) throws {
        guard !records.isEmpty else {
            // An emptied session leaves no stale file behind.
            try? FileManager.default.removeItem(at: url)
            return
        }
        try Data(render(records).utf8).write(to: url, options: .atomic)
    }

    /// Replaces the block for `record`'s source, or appends it when the clip is
    /// new. This is the download path.
    static func upsert(_ record: ClipRecord, at url: URL) throws {
        var records = read(at: url)
        if let index = records.firstIndex(where: {
            ClipRecord.isSameSource($0.sourceURL, record.sourceURL)
        }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try write(records, to: url)
    }

    /// Sets the cut of one clip: the block whose link is `source` when that is
    /// known, else the one named `filename`, else a new block for it. An empty
    /// cut takes the clip's `CUT` line out; a clip added from disk then has
    /// nothing left to record, so its block goes.
    ///
    /// `renamedTo` is the clip's name after its file was renamed to carry the
    /// cut (`ClipCutName`). The block takes that name, so the clip is still
    /// found by it the next time it is added.
    static func setCut(
        _ cut: String,
        filename: String,
        renamedTo newFilename: String? = nil,
        source: String? = nil,
        at url: URL
    ) throws {
        var records = read(at: url)
        let cut = trimmed(cut)
        let bySource = source.flatMap { source in
            records.firstIndex { ClipRecord.isSameSource($0.sourceURL, source) }
        }
        if let index = bySource ?? records.firstIndex(where: { $0.filename == filename }) {
            records[index].timestamp = cut
            if let newFilename { records[index].filename = newFilename }
            if cut.isEmpty, trimmed(records[index].sourceURL).isEmpty { records.remove(at: index) }
        } else if !cut.isEmpty {
            records.append(ClipRecord(
                filename: newFilename ?? filename, timestamp: cut, sourceURL: source ?? ""
            ))
        } else {
            return
        }
        try write(records, to: url)
    }
}
