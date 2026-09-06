import Foundation

/// Pulls the name of the person *in* a clip out of the text of the post that
/// carried it.
///
/// The account that posts a clip is usually not the person in it — aggregator
/// accounts are most of the feed — so the poster's display name is deliberately
/// never consulted. What the two common post shapes do share is that the
/// speaker leads the text:
///
///     Trump: We're going to drill baby drill
///     Trump traveled all the way to South Dakota to read a red scare speech
///
/// so one rule covers both: take the opening run of capitalized words, stopping
/// at a colon or at the first word that isn't one.
///
/// Abstains rather than guesses. A wrong name written silently into a clip's
/// notes is worse than an empty field, because the empty field is obvious and
/// the wrong name reads as correct.
enum ClipPersonName {

    /// Longest name the opening run is allowed to be. Past this the text is
    /// almost certainly a headline rather than someone's name.
    static let maxWords = 4

    /// All-caps attention markers that open a post but never name the speaker.
    /// Matched against a leading `MARKER:` / `JUST IN:` head, and used to stop
    /// the name scan from swallowing one.
    private static let markers: Set<String> = [
        "BREAKING", "NEW", "WATCH", "JUST", "EXCLUSIVE", "UPDATE", "ICYMI",
        "LOOK", "WOW", "REPORT", "ALERT", "DEVELOPING", "NOW", "LIVE", "VIDEO",
        "CLIP", "HOLY", "OMG", "WILD", "MUST",
    ]

    /// Capitalized words that open a sentence *about* someone rather than
    /// naming them. Without this, "The president appeared confused" yields a
    /// person called "The".
    private static let nonNames: Set<String> = [
        "The", "A", "An", "This", "That", "These", "Those", "It", "Its",
        "He", "She", "They", "We", "You", "I", "There", "Here",
        "What", "When", "Where", "Why", "How", "Who", "If", "So", "And",
        "But", "Or", "My", "His", "Her", "Their", "Our", "Some", "Every",
        "After", "Before", "During", "While", "Also", "Even", "Still",
    ]

    /// The speaker and what's left of the post once their name is removed.
    ///
    /// `person` is nil when no name could be read with confidence, in which
    /// case `description` is the whole (lead-stripped) text — the caller shows
    /// it as the description and leaves the person field empty to be filled in.
    static func extract(fromPostText raw: String) -> (person: String?, description: String) {
        let text = strippedLead(raw)
        guard !text.isEmpty else { return (nil, "") }

        var words: [String] = []
        var nameEnd = text.startIndex
        var index = text.startIndex

        while words.count < maxWords, index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            let wordStart = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            var word = String(text[wordStart..<index])
            // A colon ends the name run — "Trump:" is the whole speaker. Commas
            // trail names in lists and are never part of one.
            let endsRun = word.hasSuffix(":")
            while let last = word.last, last == ":" || last == "," { word.removeLast() }

            guard isNameWord(word) else { break }
            words.append(word)
            nameEnd = index
            if endsRun { break }
        }

        guard !words.isEmpty else { return (nil, text) }

        var rest = String(text[nameEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        while rest.hasPrefix(":") {
            rest.removeFirst()
            rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (words.joined(separator: " "), rest)
    }

    // MARK: - Private

    /// True for a word that can be part of a person's name: capitalized, made
    /// only of letters and the punctuation names carry (J.D., O'Rourke,
    /// Ocasio-Cortez), and not a grammatical opener or an attention marker.
    private static func isNameWord(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        guard !nonNames.contains(word), !markers.contains(word.uppercased()) else { return false }
        return word.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "\u{2019}" || $0 == "-" }
    }

    /// Drops what sits in front of the name: emoji and punctuation decoration,
    /// then an all-caps `BREAKING:` / `JUST IN:` style marker.
    private static func strippedLead(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, !first.isLetter, !first.isNumber, first != "\"" {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colon = text.firstIndex(of: ":") else { return text }
        let head = text[text.startIndex..<colon]
        let headWords = head.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let lead = headWords.first, headWords.count <= 2, markers.contains(lead),
              headWords.allSatisfy({ word in
                  word.count >= 2 && word == word.uppercased() && word.allSatisfy(\.isLetter)
              })
        else { return text }

        return String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
