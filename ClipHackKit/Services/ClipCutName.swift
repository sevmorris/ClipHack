import Foundation

/// A clip's cut, carried at the end of its file name:
///
///     Trump drill 1.13 to .55.m4a
///
/// The file name is what is in front of you while editing the clip, so the
/// cut travels with the audio instead of living only in the session's notes
/// file. A colon can't go in a file name — Finder shows it as "/" — so each one
/// is written as a period: `1:13 to :55` becomes `1.13 to .55`. The notes file
/// and the row keep the cut as it was typed.
///
/// A cut is free text, so nothing reads one back out of a name. What a rename
/// needs is to take off the cut a row already has (`baseStem`) before putting
/// the new one on.
///
/// `nonisolated`: pure string handling, used from the download service and the
/// view model alike.
nonisolated enum ClipCutName {

    /// Longest cut written into a name, in UTF-8 bytes. A cut is a few
    /// characters; this only stops a pasted paragraph from making a file name
    /// macOS refuses.
    static let maxBytes = 60

    /// The cut as it reads in a file name, or nil for a blank one.
    ///
    /// Colons become periods and "/" a hyphen, whitespace collapses to single
    /// spaces, and NUL is dropped. Leading periods stay: the cut never starts
    /// the name, so `:55 to 1:10` keeps its meaning as `.55 to 1.10`. Trailing
    /// periods go, as they do from any stem, so a rename leaves this exactly
    /// as it is and `baseStem` can find it again.
    static func fragment(_ cut: String) -> String? {
        var text = cut
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        text = YtDlpService.prefix(of: text, utf8Bytes: maxBytes)
        while text.hasSuffix(".") || text.hasSuffix(" ") { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    /// `name` with `cut` on the end: "Trump drill" and "1:13 to :55" make
    /// "Trump drill 1.13 to .55". A blank cut leaves the name alone.
    ///
    /// The name is shortened, not the cut, when the two together would pass
    /// `YtDlpService.maxStemBytes` — the cut is the part that has to survive.
    static func stem(_ name: String, cut: String) -> String {
        guard let fragment = fragment(cut) else { return name }
        let room = YtDlpService.maxStemBytes - fragment.utf8.count - 1
        let base = YtDlpService.prefix(of: name, utf8Bytes: room)
            .trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? fragment : "\(base) \(fragment)"
    }

    /// `stem` without `cut` on its end, or `stem` unchanged when it doesn't
    /// end with it — a clip named before cuts went into names, or one renamed
    /// by hand since.
    static func baseStem(_ stem: String, cut: String) -> String {
        guard let fragment = fragment(cut), stem.hasSuffix(" " + fragment) else { return stem }
        return String(stem.dropLast(fragment.count + 1))
    }
}
