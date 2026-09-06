import Foundation

/// The `Person — description` line that opens a clip's notes.
///
/// It sits *inside* the notes rather than in fields of its own, because the
/// notes file's on-disk shape is a compatibility surface (see `ClipNotesFile`)
/// — anything already reading those files keeps working, since the notes body
/// was always free text. Line one says who is in the clip and what it is;
/// every line below it stays free for timings and scratch.
enum ClipNotesLine {

    /// Written between person and description. Em dash.
    static let separator = "\u{2014}"

    // MARK: - Reading

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

    // MARK: - Writing

    /// The line as it is stored in the notes file: `Person — what they said`.
    ///
    /// A person with no description still writes its separator, so the line
    /// reads as a name rather than as a description that happens to be short.
    static func notesLine(person: String, description: String) -> String {
        let name = person.trimmingCharacters(in: .whitespaces)
        let text = description.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return text }
        if text.isEmpty { return "\(name) \(separator)" }
        return "\(name) \(separator) \(text)"
    }

    /// Assembles a notes body from its parts: the line above, then the scratch
    /// lines beneath it verbatim.
    static func compose(person: String, description: String, extra: String) -> String {
        let head = notesLine(person: person, description: description)
        guard !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return head }
        return head.isEmpty ? extra : head + "\n" + extra
    }
}
