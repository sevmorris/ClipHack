import Foundation

/// One notes file per session, holding every clip in it, laid out to work from
/// while editing the clips: a summary line, then a short block per clip with
/// the file name flush left, its cut right under it, and the source link last.
///
///     HT_0385 2026-10-13/clips/HT_0385 2026-10-13.txt
///
///     HT_0385 2026-10-13 · 2 clips · 1 cut
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
/// source, and anything else indented its notes.
///
/// A download records its filename, the cut when one was entered, and the
/// source URL — never the person or the notes. Blocks an earlier version wrote
/// with notes in them still parse, and keep their notes when the file is
/// rewritten: the parser cannot always tell a free-form cut from notes, so
/// dropping notes on the way out would eat cuts too.
///
/// Files in the layout before this one — `ClipNotesFile` bodies between `---`
/// rules — still read, and come back in this layout the next time the file is
/// written.
///
/// Maintained, never appended. ClipHack rewrites the file from what it holds,
/// so a re-download or an edit replaces a clip's block instead of stacking a
/// second one after it. That is the whole reason the per-clip files replaced
/// the daily appending log this returns to: an append-only file grows a history
/// and then has to be pruned by hand.
enum SessionNotesFile {

    /// Rule between clips in the layout before this one. Still read.
    static let separator = "---"

    /// Marks a clip's cut, so it stands out from the link under it.
    static let cutLabel = "CUT"

    /// Stands in for the file name of an old block that recorded none, so the
    /// block still has a flush-left line to start it.
    static let unnamed = "(no file name)"

    /// Every line of a block after its file name.
    private static let indent = "    "

    /// The session's notes file, named after the session itself.
    static func url(inClipsFolder folder: URL, title: String) -> URL {
        folder.appendingPathComponent("\(title).txt")
    }

    // MARK: - Rendering

    /// The whole file. `title`, the session's name, heads the summary line.
    static func render(_ records: [ClipNotesFile.Record], title: String? = nil) -> String {
        var lines = [summary(of: records, title: title)]
        for record in records {
            lines.append("")
            lines.append(contentsOf: block(for: record))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "HT_0385 2026-10-13 · 13 clips · 1 cut". The cut count is left off when
    /// there are none.
    static func summary(of records: [ClipNotesFile.Record], title: String?) -> String {
        let cuts = records.filter { !trimmed($0.timestamp).isEmpty }.count
        var parts = [count(records.count, "clip")]
        if cuts > 0 { parts.append(count(cuts, "cut")) }
        if let title, !trimmed(title).isEmpty { parts.insert(trimmed(title), at: 0) }
        return parts.joined(separator: " · ")
    }

    private static func block(for record: ClipNotesFile.Record) -> [String] {
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
    /// the path, and `ClipNotesFile.isSameSource` matches X links by that id.
    /// Every other link stays exactly as recorded: a YouTube video's id lives
    /// in its query.
    static func tidied(_ link: String) -> String {
        let link = trimmed(link)
        guard XPostText.statusID(from: link) != nil,
              var parts = URLComponents(string: link)
        else { return link }
        parts.query = nil
        parts.fragment = nil
        return parts.string ?? link
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> [ClipNotesFile.Record] {
        isEarlierLayout(text) ? parseEarlierLayout(text) : parseBlocks(text)
    }

    /// The layout before this one has no summary line and nothing indented,
    /// with clips between `---` rules, and every block ends in its link. A
    /// one-clip file of that shape has no rule at all, so it shows itself by a
    /// link at the left edge. A file of clips added by hand — names alone, no
    /// links — is this layout even with its summary line deleted.
    static func isEarlierLayout(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        if let first = lines.first(where: { !trimmed($0).isEmpty }), isSummary(first) { return false }
        if lines.contains(where: { trimmed($0) == separator }) { return true }
        return !lines.contains(where: isIndented)
            && lines.contains(where: { !isIndented($0) && isLink(trimmed($0)) })
    }

    private static func parseEarlierLayout(_ text: String) -> [ClipNotesFile.Record] {
        text
            .components(separatedBy: "\n")
            .split(whereSeparator: { trimmed(String($0)) == separator })
            .map { $0.joined(separator: "\n") }
            .compactMap(ClipNotesFile.parse)
    }

    private static func parseBlocks(_ text: String) -> [ClipNotesFile.Record] {
        var records: [ClipNotesFile.Record] = []
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
            } else if name == nil, records.isEmpty, isSummary(line) {
                continue
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
    /// is the source, and the rest is notes. With no link, the last line is
    /// taken for the source, as `ClipNotesFile.parse` does for an old file
    /// that lost its URL; with no `CUT` label, a line that reads as a cut is
    /// the cut, so one typed in by hand still counts.
    private static func record(named name: String, body: [String]) -> ClipNotesFile.Record {
        var lines = body
        var cut = ""
        if let index = lines.firstIndex(where: { cutValue($0) != nil }) {
            cut = cutValue(lines.remove(at: index)) ?? ""
        }
        var source = ""
        if let index = lines.lastIndex(where: isLink) ?? lines.lastIndex(where: { !$0.isEmpty }) {
            source = lines.remove(at: index)
        }
        if cut.isEmpty, let index = lines.firstIndex(where: ClipNotesFile.isTimestamp) {
            cut = trimmed(lines.remove(at: index))
        }
        return ClipNotesFile.Record(
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
        return asWritten || ClipNotesFile.isTimestamp(value) ? value : nil
    }

    /// A line typed flush left by hand that still belongs to the clip above:
    /// its cut or its link, never the name of the next clip.
    private static func belongsToTheClipAbove(_ line: String) -> Bool {
        cutValue(line) != nil || isLink(line) || ClipNotesFile.isTimestamp(line)
    }

    private static func isSummary(_ line: String) -> Bool {
        trimmed(line).range(
            of: #"^(?:.+ · )?\d+ clips?(?: · \d+ cuts?)?$"#, options: .regularExpression
        ) != nil
    }

    private static func isLink(_ line: String) -> Bool {
        line.contains("://") && !line.contains(" ")
    }

    private static func isIndented(_ line: String) -> Bool {
        (line.first == " " || line.first == "\t") && !trimmed(line).isEmpty
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let title = url.deletingPathExtension().lastPathComponent
        try Data(render(records, title: title).utf8).write(to: url, options: .atomic)
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
            records.append(ClipNotesFile.Record(filename: name, notes: "", timestamp: "", sourceURL: ""))
            added += 1
        }
        if added > 0 { try write(records, to: url) }
        return added
    }

    /// Sets the cut of one clip: the block whose link is `source` when that is
    /// known, else the one named `filename`, else a new block for it. An empty
    /// cut removes the clip's `CUT` line and adds nothing.
    static func setCut(_ cut: String, filename: String, source: String? = nil, at url: URL) throws {
        var records = read(at: url)
        let cut = trimmed(cut)
        let bySource = source.flatMap { source in
            records.firstIndex { ClipNotesFile.isSameSource($0.sourceURL, source) }
        }
        if let index = bySource ?? records.firstIndex(where: { $0.filename == filename }) {
            records[index].timestamp = cut
        } else if !cut.isEmpty {
            records.append(ClipNotesFile.Record(
                filename: filename, notes: "", timestamp: cut, sourceURL: source ?? ""
            ))
        } else {
            return
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
