import XCTest
@testable import ClipHackKit

@MainActor
final class ClipNotesLineTests: XCTestCase {

    // MARK: - Writing the line

    func testStoredLineUsesAnEmDash() {
        XCTAssertEqual(
            ClipNotesLine.notesLine(person: "Trump", description: "said the thing"),
            "Trump — said the thing"
        )
    }

    func testNoPersonMeansNoSeparator() {
        XCTAssertEqual(ClipNotesLine.notesLine(person: "  ", description: "said the thing"), "said the thing")
    }

    /// A name with nothing said yet still writes its dash, so the line reads as
    /// a name rather than as a very short description.
    func testPersonWithNoDescriptionKeepsItsSeparator() {
        XCTAssertEqual(ClipNotesLine.notesLine(person: "Trump", description: ""), "Trump —")
    }

    // MARK: - Composing a notes body

    func testComposeKeepsTheLinesBelowVerbatim() {
        XCTAssertEqual(
            ClipNotesLine.compose(
                person: "Trump",
                description: "said the thing",
                extra: ":30 to :12\nsecond scratch line"
            ),
            "Trump — said the thing\n:30 to :12\nsecond scratch line"
        )
    }

    func testComposeWithNoExtraIsJustTheLine() {
        XCTAssertEqual(
            ClipNotesLine.compose(person: "Trump", description: "said the thing", extra: "  \n "),
            "Trump — said the thing"
        )
    }

    func testComposeWithNoLineIsJustTheExtra() {
        XCTAssertEqual(
            ClipNotesLine.compose(person: " ", description: " ", extra: ":30 to :12"),
            ":30 to :12"
        )
    }

    // MARK: - The popover's notes box

    func testNotesBoxSplitsOnLinesNotSeparators() {
        // An em dash the user types inside a description must survive: the
        // popover keeps the person in its own field.
        let box = ClipNotesLine.splitNotesBox("said one thing — then another\n:30 to :12")
        XCTAssertEqual(box.description, "said one thing — then another")
        XCTAssertEqual(box.extra, ":30 to :12")
    }

    func testEmptyNotesBox() {
        let box = ClipNotesLine.splitNotesBox("")
        XCTAssertEqual(box.description, "")
        XCTAssertEqual(box.extra, "")
    }
}
