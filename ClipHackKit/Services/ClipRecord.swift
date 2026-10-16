import Foundation

/// One clip's block in the session's notes file (`SessionNotesFile`): the name
/// it was downloaded under, its cut, and its source link.
///
/// `nonisolated`: pure values and text matching.
nonisolated struct ClipRecord: Equatable {
    /// The clip's file name when it was recorded. A rename by hand doesn't
    /// rewrite it, so treat it as a hint rather than the truth about what is
    /// on disk now; Set Cut… does rewrite it.
    var filename: String
    /// The cut, e.g. "1:13 to :55". Empty when none was entered.
    var timestamp: String = ""
    /// Where a download came from. Empty for a clip added from disk, which
    /// has a block only for its cut.
    var sourceURL: String = ""

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
