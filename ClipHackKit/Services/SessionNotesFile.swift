import Foundation

/// One notes file per session, holding every clip in it, laid out to work from
/// while editing the clips: a short block per clip with the file name flush
/// left, its cut right under it, and the source link last.
///
///     HT_0385 2026-10-13/clips/HT_0385 2026-10-13.txt
///
///     CSPAN_-_President_Trump_….m4a
///         https://x.com/cspan/status/2109039198422405195
///
///     This_Week_-_Kansas_Senate_….m4a
///         CUT  1:23 to :52
///         https://x.com/thisweekabc/status/2109318964635730038
///
/// The file name starts a clip's block and every other line of it is indented.
/// That is what the eye scans for, and what the parser keys on: a flush-left
/// line is the next clip, an indented `CUT` line its cut, an indented link its
/// source, and anything else indented is kept as typed (`ClipRecord.notes`).
///
/// A download records its filename, the cut when one was entered, and the
/// source URL. The show's clip skill reads the file; nothing older than this
/// layout is still around to read, since each week's prep clears the last
/// episode's clips folder out.
///
/// Maintained, never appended. ClipHack rewrites the file from what it holds,
/// so a re-download or an edit replaces a clip's block instead of stacking a
/// second one after it.
///
/// `nonisolated`: pure text and file handling, and it passes its own helpers (`isIndented`, `isLink`, `trimmed`) to `contains`,
/// `lastIndex` and `map` as plain function values.
nonisolated enum SessionNotesFile {

    /// Marks a clip's cut, so it stands out from the link under it.
    static let cutLabel = "CUT"

    /// Stands in for the file name of a block that has none — one typed by
    /// hand without it — so the block still has a flush-left line to start it.
    static let unnamed = "(no file name)"

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
        let name = trimmed(record.filename)
        var lines = [name.isEmpty ? unnamed : name]
        let cut = trimmed(record.timestamp)
        if !cut.isEmpty { lines.append("\(indent)\(cutLabel)  \(cut)") }
        let notes = trimmed(record.notes)
        if !notes.isEmpty {
            lines += notes.components(separatedBy: "\n").map {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return line.isEmpty ? "" : indent + line
            }
        }
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

    static func parse(_ text: String) -> [ClipRecord] {
        var records: [ClipRecord] = []
        var name: String?
        var body: [String] = []

        func finish() {
            if let name { records.append(record(named: name, body: body)) }
            name = nil
            body = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = trimmed(raw)
            if line.isEmpty {
                if name != nil { body.append("") }
            } else if isIndented(raw) || (name != nil && belongsToTheClipAbove(line)) {
                if name == nil { name = "" }
                body.append(line)
            } else {
                finish()
                name = line
            }
        }
        finish()
        return records
    }

    /// A block's lines after its name: a `CUT` line is the cut, the last link
    /// is the source, and the rest is kept as typed. With no `CUT` label, a
    /// line that reads as a cut is the cut, so one typed in by hand still
    /// counts. A clip added from disk has no link, so its source is empty.
    private static func record(named name: String, body: [String]) -> ClipRecord {
        var lines = body
        var cut = ""
        if let index = lines.firstIndex(where: { cutValue($0) != nil }) {
            cut = cutValue(lines.remove(at: index)) ?? ""
        }
        var source = ""
        if let index = lines.lastIndex(where: isLink) {
            source = lines.remove(at: index)
        }
        if cut.isEmpty, let index = lines.firstIndex(where: ClipRecord.isTimestamp) {
            cut = trimmed(lines.remove(at: index))
        }
        return ClipRecord(
            filename: name == unnamed ? "" : name,
            notes: trimmed(lines.joined(separator: "\n")),
            timestamp: cut,
            sourceURL: source
        )
    }

    /// "CUT  1:23 to :52" → "1:23 to :52". Nil for any other line. After the
    /// label as ClipHack writes it, anything is the cut; after one typed in
    /// lowercase, only a timestamp is, so notes reading "Cut the crap…" stay notes.
    private static func cutValue(_ line: String) -> String? {
        // One optional colon after the label, then space: a cut that starts
        // with its own colon (":40 to :14") keeps it.
        let pattern = "^\(cutLabel)\\b:?\\s+"
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let value = trimmed(String(line[range.upperBound...]))
        guard !value.isEmpty else { return nil }
        let asWritten = line.hasPrefix(cutLabel)
        return asWritten || ClipRecord.isTimestamp(value) ? value : nil
    }

    /// A line typed flush left by hand that still belongs to the clip above:
    /// its cut or its link, never the name of the next clip.
    private static func belongsToTheClipAbove(_ line: String) -> Bool {
        cutValue(line) != nil || isLink(line) || ClipRecord.isTimestamp(line)
    }

    private static func isLink(_ line: String) -> Bool {
        line.contains("://") && !line.contains(" ")
    }

    private static func isIndented(_ line: String) -> Bool {
        (line.first == " " || line.first == "\t") && !trimmed(line).isEmpty
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
    /// new. This is the download path — the panel rewrites the whole file.
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

    // MARK: - Clips added by hand

    /// Lists clips added from disk — dragged in or opened, not downloaded — by
    /// name alone, since there is no link to record. A file that already has a
    /// block, a download or an earlier add, is left as it is. Returns how many
    /// were added.
    @discardableResult
    static func recordAddedFiles(named filenames: [String], at url: URL) throws -> Int {
        var records = read(at: url)
        var added = 0
        for name in filenames.map(trimmed) where !name.isEmpty {
            guard !records.contains(where: { $0.filename == name }) else { continue }
            records.append(ClipRecord(filename: name, notes: "", timestamp: "", sourceURL: ""))
            added += 1
        }
        if added > 0 { try write(records, to: url) }
        return added
    }

    /// Sets the cut of one clip: the block whose link is `source` when that is
    /// known, else the one named `filename`, else a new block for it. An empty
    /// cut removes the clip's `CUT` line and adds nothing.
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
        } else if !cut.isEmpty {
            records.append(ClipRecord(
                filename: newFilename ?? filename, notes: "", timestamp: cut, sourceURL: source ?? ""
            ))
        } else {
            return
        }
        try write(records, to: url)
    }
}
