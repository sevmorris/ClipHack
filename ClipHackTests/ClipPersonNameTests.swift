import XCTest
@testable import ClipHackKit

@MainActor
final class ClipPersonNameTests: XCTestCase {

    // MARK: - The two shapes clips actually arrive in

    func testColonPrefixNamesTheSpeaker() {
        let result = ClipPersonName.extract(fromPostText: "Trump: We are going to drill baby drill")
        XCTAssertEqual(result.person, "Trump")
        XCTAssertEqual(result.description, "We are going to drill baby drill")
    }

    func testProseLeadingWithTheNameSplitsThere() {
        // The real atrupar payload shape from XPostTextTests.
        let result = ClipPersonName.extract(
            fromPostText: "Trump traveled all the way to South Dakota to read a half-baked red scare speech straight out of 1950"
        )
        XCTAssertEqual(result.person, "Trump")
        XCTAssertEqual(
            result.description,
            "traveled all the way to South Dakota to read a half-baked red scare speech straight out of 1950"
        )
    }

    func testMultiWordNames() {
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "JD Vance says the quiet part out loud").person,
            "JD Vance"
        )
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "Marjorie Taylor Greene: I will not be voting for this bill").person,
            "Marjorie Taylor Greene"
        )
    }

    func testNamesKeepTheirOwnPunctuation() {
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "Alexandria Ocasio-Cortez: not a chance").person,
            "Alexandria Ocasio-Cortez"
        )
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "Beto O'Rourke says no").person,
            "Beto O'Rourke"
        )
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "J.D. Vance: no comment").person,
            "J.D. Vance"
        )
    }

    // MARK: - Lead-in noise

    func testAllCapsMarkerIsNotTheSpeaker() {
        let result = ClipPersonName.extract(fromPostText: "BREAKING: Newsom signs the bill into law")
        XCTAssertEqual(result.person, "Newsom")
        XCTAssertEqual(result.description, "signs the bill into law")
    }

    func testMarkerWithTwoWords() {
        XCTAssertEqual(
            ClipPersonName.extract(fromPostText: "JUST IN: Bernie Sanders destroys the CEO").person,
            "Bernie Sanders"
        )
    }

    func testEmojiDecorationIsStripped() {
        let result = ClipPersonName.extract(fromPostText: "\u{1F6A8} Trump: something happened")
        XCTAssertEqual(result.person, "Trump")
        XCTAssertEqual(result.description, "something happened")
    }

    func testNameOnItsOwnLineAboveTheBody() {
        let result = ClipPersonName.extract(fromPostText: "Trump:\n\nWe are going to win")
        XCTAssertEqual(result.person, "Trump")
        XCTAssertEqual(result.description, "We are going to win")
    }

    // MARK: - Abstaining

    // The whole point: a wrong name reads as correct, an empty field does not.

    func testSentenceAboutSomeoneYieldsNoName() {
        let result = ClipPersonName.extract(fromPostText: "The president appeared confused during the press conference")
        XCTAssertNil(result.person)
        XCTAssertEqual(
            result.description,
            "The president appeared confused during the press conference",
            "abstaining must leave the text whole for the description"
        )
    }

    func testLowercaseOpeningYieldsNoName() {
        let result = ClipPersonName.extract(fromPostText: "just setting up my twttr")
        XCTAssertNil(result.person)
        XCTAssertEqual(result.description, "just setting up my twttr")
    }

    func testGrammaticalOpenersAreNotNames() {
        for opener in ["This is worth watching", "They said it out loud", "After the vote he left"] {
            XCTAssertNil(
                ClipPersonName.extract(fromPostText: opener).person,
                "\"\(opener)\" must not produce a name"
            )
        }
    }

    func testEmptyTextYieldsNothing() {
        let result = ClipPersonName.extract(fromPostText: "   \n  ")
        XCTAssertNil(result.person)
        XCTAssertEqual(result.description, "")
    }

    // MARK: - Bounds

    func testNameRunStopsAtTheWordCap() {
        let result = ClipPersonName.extract(fromPostText: "Alpha Bravo Charlie Delta Echo Foxtrot")
        XCTAssertEqual(result.person, "Alpha Bravo Charlie Delta")
        XCTAssertEqual(result.description, "Echo Foxtrot")
    }

    func testColonEndsTheRunEvenBelowTheCap() {
        let result = ClipPersonName.extract(fromPostText: "Alpha Bravo: Charlie Delta")
        XCTAssertEqual(result.person, "Alpha Bravo")
        XCTAssertEqual(result.description, "Charlie Delta")
    }
}
