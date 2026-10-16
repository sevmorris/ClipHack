import Foundation

/// One clip's block in the session's notes file (`SessionNotesFile`): the name
/// it was downloaded or added under, its cut, its source link, and any other
/// lines typed into the block by hand.
///
/// `nonisolated`: pure values and text matching, and `SessionNotesFile` passes
/// `isTimestamp` around as a plain function value.
nonisolated struct ClipRecord: Equatable {
    /// The clip's file name when it was recorded. A rename by hand doesn't
    /// rewrite it, so treat it as a hint rather than the truth about what is
    /// on disk now; Set Cut… does rewrite it.
    var filename: String
    /// Lines of the block that are neither its cut nor its link, typed by
    /// hand. ClipHack writes none, and keeps them when it rewrites the file:
    /// the parser can't always tell a free-form cut from other text, so
    /// dropping them would eat cuts too.
    var notes: String
    /// The cut, e.g. "1:13 to :55". Empty when none was entered.
    var timestamp: String = ""
    var sourceURL: String

    /// True when a line is an in/out timestamp rather than prose — "1:13 to :55",
    /// ":30 to :12", "To :17", "0:05", ":18 to end".
    ///
    /// A colon is required, so a stray number in a line typed by hand is not
    /// mistaken for a cut.
    static func isTimestamp(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains("\n") else { return false }
        let pattern = #"^(?:to\s+)?\d{0,2}:\d{1,2}(?:\s*(?:to|-|–|—|>)\s*(?:\d{0,2}:?\d{1,2}|end))?$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True when two source URLs point at the same clip. Exact match, plus X
    /// post URLs compared by status ID so the same post pasted with different
    /// tracking params still matches. Deliberately does NOT ignore query
    /// strings in general — for YouTube and friends the video id lives there.
    static func isSameSource(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if a == b { return !a.isEmpty }
        if let idA = XPostLink.statusID(from: a), let idB = XPostLink.statusID(from: b) {
            return idA == idB
        }
        return false
    }
}
