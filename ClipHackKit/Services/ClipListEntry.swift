import Foundation

/// The `Person — description` line that opens a clip's notes, and the numbered
/// list built from a folder's worth of them.
///
/// The clip list is carried *inside* the notes rather than in a new field or a
/// second sidecar, because the sidecar's on-disk shape is a compatibility
/// surface (see `ClipNotesFile`) — anything already reading those files keeps
/// working, since the notes body was always free text. Line one is the list
/// entry; every line below it stays free for timings and scratch.
enum ClipListEntry {

    /// Written between person and description **in the notes file**. Em dash.
    ///
    /// Storage only — it is what lets a stored line be split back into the two
    /// fields the panel edits. The copied list drops it and lets the
    /// capitalized name do the separating instead; see `exportLine`.
    static let separator = "\u{2014}"

    /// A parsed notes body: its list line, split, plus whatever followed.
    struct Parsed: Equatable {
        /// Empty when the line carries no separator — the person is unknown and
        /// the whole line is treated as the description.
        var person: String
        var description: String
        /// Lines below the first, verbatim. Timings and scratch live here.
        var extra: String

        init(person: String = "", description: String = "", extra: String = "") {
            self.person = person
            self.description = description
            self.extra = extra
        }
    }

    // MARK: - Reading

    /// Splits a notes body into its list line and the free lines beneath it.
    static func parse(notes: String) -> Parsed {
        let lines = notes.components(separatedBy: "\n")
        guard let first = lines.first else { return Parsed() }
        let split = splitLine(first)
        return Parsed(
            person: split.person,
            description: split.description,
            extra: lines.dropFirst().joined(separator: "\n")
        )
    }

    /// Splits the download popover's notes box into its first line and the
    /// lines below it.
    ///
    /// Deliberately does *not* look for a separator. The popover keeps the
    /// person in its own field, so its notes box is description-then-scratch —
    /// an em dash the user types inside a description has to survive intact.
    static func splitNotesBox(_ notes: String) -> (description: String, extra: String) {
        let lines = notes.components(separatedBy: "\n")
        guard let first = lines.first else { return ("", "") }
        return (
            first.trimmingCharacters(in: .whitespaces),
            lines.dropFirst().joined(separator: "\n")
        )
    }

    /// Splits one line on the first separator it carries.
    ///
    /// Reading is lenient where writing is not: an en dash or a spaced hyphen
    /// parses too, so a line typed by hand — or written before this format
    /// existed — still lands in the right fields. Only the first separator
    /// counts, so a description may contain more of them.
    static func splitLine(_ line: String) -> (person: String, description: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for dash in [separator, "\u{2013}"] {
            if let range = trimmed.range(of: dash) {
                return (
                    String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                )
            }
        }
        // A hyphen only separates when spaced — names carry unspaced ones
        // (Ocasio-Cortez), and those must stay whole.
        if let range = trimmed.range(of: " - ") {
            return (
                String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            )
        }
        if trimmed.hasSuffix(" -") {
            return (String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces), "")
        }
        // No separator: the person is unknown, not empty-named.
        return ("", trimmed)
    }

    // MARK: - Writing

    /// The line as it is stored in the notes file: `Person — what they said`.
    ///
    /// A person with no description still writes its separator, so the line
    /// round-trips back into the same two fields instead of reading as a
    /// description with no person.
    static func notesLine(person: String, description: String) -> String {
        let name = person.trimmingCharacters(in: .whitespaces)
        let text = description.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return text }
        if text.isEmpty { return "\(name) \(separator)" }
        return "\(name) \(separator) \(text)"
    }

    /// Rebuilds a notes body from its parts — the inverse of `parse`.
    static func compose(person: String, description: String, extra: String) -> String {
        let head = notesLine(person: person, description: description)
        guard !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return head }
        return head.isEmpty ? extra : head + "\n" + extra
    }

    // MARK: - Export

    /// The finished clip list: one numbered line per entry, in the order given.
    ///
    /// Entries with neither a person nor a description are dropped — a clip
    /// whose notes were never filled in would otherwise take a number and
    /// contribute a blank line, and renumbering by hand is the thing this
    /// exists to avoid.
    /// True when an entry carries enough to be worth a number.
    ///
    /// The panel numbers its rows with this too, so what you see beside a row
    /// is the number it will actually export as.
    static func isListable(person: String, description: String) -> Bool {
        !person.trimmingCharacters(in: .whitespaces).isEmpty
            || !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The line as it is copied out: the person in capitals, then what they
    /// said, with nothing between them.
    ///
    /// No dash. The capitals do the separating, which is why the name is
    /// uppercased here rather than stored that way — the notes file keeps the
    /// name as it was typed, so editing it back in the panel shows what you
    /// wrote, not a shout.
    static func exportLine(person: String, description: String) -> String {
        let name = person.trimmingCharacters(in: .whitespaces).uppercased()
        let text = description.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return text }
        if text.isEmpty { return name }
        return "\(name) \(text)"
    }

    static func numberedList(_ entries: [Parsed]) -> String {
        entries
            .filter { isListable(person: $0.person, description: $0.description) }
            .enumerated()
            .map { index, entry in
                "\(index + 1)) \(exportLine(person: entry.person, description: entry.description))"
            }
            .joined(separator: "\n")
    }
}
