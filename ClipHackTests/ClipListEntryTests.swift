import XCTest
@testable import ClipHackKit

@MainActor
final class ClipListEntryTests: XCTestCase {

    // MARK: - Writing the line

    func testStoredLineUsesAnEmDash() {
        XCTAssertEqual(
            ClipListEntry.notesLine(person: "Trump", description: "said the thing"),
            "Trump — said the thing"
        )
    }

    func testNoPersonWritesTheDescriptionAlone() {
        XCTAssertEqual(ClipListEntry.notesLine(person: "  ", description: "said the thing"), "said the thing")
    }

    func testPersonWithNoDescriptionKeepsItsSeparator() {
        // So the line round-trips back into the person field rather than
        // reading as a description with no person.
        let line = ClipListEntry.notesLine(person: "Trump", description: "")
        XCTAssertEqual(line, "Trump —")
        XCTAssertEqual(ClipListEntry.splitLine(line).person, "Trump")
        XCTAssertEqual(ClipListEntry.splitLine(line).description, "")
    }

    // MARK: - Reading the line

    func testSplitsOnEmDash() {
        let split = ClipListEntry.splitLine("Trump — said the thing")
        XCTAssertEqual(split.person, "Trump")
        XCTAssertEqual(split.description, "said the thing")
    }

    func testReadingToleratesEnDashAndSpacedHyphen() {
        for line in ["Trump – said the thing", "Trump - said the thing"] {
            let split = ClipListEntry.splitLine(line)
            XCTAssertEqual(split.person, "Trump", "\(line)")
            XCTAssertEqual(split.description, "said the thing", "\(line)")
        }
    }

    func testUnspacedHyphenInANameIsNotASeparator() {
        let split = ClipListEntry.splitLine("Alexandria Ocasio-Cortez — said the thing")
        XCTAssertEqual(split.person, "Alexandria Ocasio-Cortez")
        XCTAssertEqual(split.description, "said the thing")
    }

    func testOnlyTheFirstSeparatorCounts() {
        let split = ClipListEntry.splitLine("Trump — said one thing — then another")
        XCTAssertEqual(split.person, "Trump")
        XCTAssertEqual(split.description, "said one thing — then another")
    }

    func testLineWithNoSeparatorIsAllDescription() {
        let split = ClipListEntry.splitLine("raw post text with no name in front")
        XCTAssertEqual(split.person, "", "an unknown person is not an empty name")
        XCTAssertEqual(split.description, "raw post text with no name in front")
    }

    // MARK: - Round trip through a notes body

    func testParseKeepsTheLinesBelowVerbatim() {
        let parsed = ClipListEntry.parse(notes: "Trump — said the thing\n:30 to :12\nsecond scratch line")
        XCTAssertEqual(parsed.person, "Trump")
        XCTAssertEqual(parsed.description, "said the thing")
        XCTAssertEqual(parsed.extra, ":30 to :12\nsecond scratch line")
    }

    func testComposeIsTheInverseOfParse() {
        let original = "Trump — said the thing\n:30 to :12"
        let parsed = ClipListEntry.parse(notes: original)
        XCTAssertEqual(
            ClipListEntry.compose(person: parsed.person, description: parsed.description, extra: parsed.extra),
            original
        )
    }

    func testComposeWithNoExtraIsJustTheLine() {
        XCTAssertEqual(
            ClipListEntry.compose(person: "Trump", description: "said the thing", extra: "  \n "),
            "Trump — said the thing"
        )
    }

    // MARK: - The popover's notes box

    func testNotesBoxSplitsOnLinesNotSeparators() {
        // An em dash the user types inside a description must survive: the
        // popover keeps the person in its own field.
        let box = ClipListEntry.splitNotesBox("said one thing — then another\n:30 to :12")
        XCTAssertEqual(box.description, "said one thing — then another")
        XCTAssertEqual(box.extra, ":30 to :12")
    }

    func testEmptyNotesBox() {
        let box = ClipListEntry.splitNotesBox("")
        XCTAssertEqual(box.description, "")
        XCTAssertEqual(box.extra, "")
    }

    // MARK: - The exported list

    func testExportCapitalizesTheNameAndDropsTheDash() {
        XCTAssertEqual(
            ClipListEntry.exportLine(person: "JD Vance", description: "said the thing"),
            "JD VANCE said the thing"
        )
    }

    func testExportOfAPersonWithNoDescriptionIsJustTheName() {
        XCTAssertEqual(ClipListEntry.exportLine(person: "Trump", description: ""), "TRUMP")
    }

    func testExportWithNoPersonIsTheDescriptionAlone() {
        XCTAssertEqual(
            ClipListEntry.exportLine(person: "", description: "something happened"),
            "something happened"
        )
    }

    func testExportingDoesNotChangeWhatIsStored() {
        // The notes file keeps the name as it was typed — the capitals are put
        // on at export, so editing a row shows what you wrote.
        let stored = ClipListEntry.compose(person: "JD Vance", description: "said the thing", extra: "")
        XCTAssertEqual(stored, "JD Vance — said the thing")
        XCTAssertEqual(ClipListEntry.parse(notes: stored).person, "JD Vance")
    }

    func testNumberedListFormat() {
        let entries = [
            ClipListEntry.Parsed(person: "Trump", description: "said the thing"),
            ClipListEntry.Parsed(person: "JD Vance", description: "said the other thing"),
        ]
        XCTAssertEqual(
            ClipListEntry.numberedList(entries),
            "1) TRUMP said the thing\n2) JD VANCE said the other thing"
        )
    }

    func testBlankEntriesAreDroppedAndDoNotConsumeANumber() {
        let entries = [
            ClipListEntry.Parsed(person: "Trump", description: "first"),
            ClipListEntry.Parsed(person: "  ", description: "   "),
            ClipListEntry.Parsed(person: "Vance", description: "second"),
        ]
        XCTAssertEqual(
            ClipListEntry.numberedList(entries),
            "1) TRUMP first\n2) VANCE second"
        )
    }

    func testEntryWithOnlyADescriptionStillGetsANumber() {
        let entries = [ClipListEntry.Parsed(person: "", description: "something happened")]
        XCTAssertEqual(ClipListEntry.numberedList(entries), "1) something happened")
    }

    func testEmptyListIsEmptyString() {
        XCTAssertEqual(ClipListEntry.numberedList([]), "")
    }

    func testIsListableMatchesWhatNumberedListKeeps() {
        XCTAssertTrue(ClipListEntry.isListable(person: "Trump", description: ""))
        XCTAssertTrue(ClipListEntry.isListable(person: "", description: "something"))
        XCTAssertFalse(ClipListEntry.isListable(person: " ", description: "\t"))
    }
}
