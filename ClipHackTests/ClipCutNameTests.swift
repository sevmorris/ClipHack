import XCTest
@testable import ClipHackKit

final class ClipCutNameTests: XCTestCase {

    // MARK: - fragment

    func testColonsBecomePeriods() {
        XCTAssertEqual(ClipCutName.fragment("1:13 to :55"), "1.13 to .55")
        XCTAssertEqual(ClipCutName.fragment(":18 to end"), ".18 to end",
                       "a leading period stays: the cut never starts the name")
        XCTAssertEqual(ClipCutName.fragment("to :03"), "to .03")
    }

    func testSlashesAndWhitespaceAreTidied() {
        XCTAssertEqual(ClipCutName.fragment("  1:13   to\n:55 / 2:10 "), "1.13 to .55 - 2.10")
        XCTAssertEqual(ClipCutName.fragment("1:13\0 to :55"), "1.13 to .55")
    }

    func testTrailingPeriodsGoSoARenameLeavesItAlone() {
        XCTAssertEqual(ClipCutName.fragment("1:13 to 1:"), "1.13 to 1")
        let stem = ClipCutName.stem("Clip", cut: "1:13 to 1:")
        XCTAssertEqual(YtDlpService.sanitizedStem(stem), stem)
    }

    func testABlankCutHasNoFragment() {
        XCTAssertNil(ClipCutName.fragment(""))
        XCTAssertNil(ClipCutName.fragment("  \n "))
        XCTAssertNil(ClipCutName.fragment(":"))
    }

    func testALongCutIsCapped() {
        let fragment = ClipCutName.fragment(String(repeating: "1:13 to :55 ", count: 20))
        XCTAssertLessThanOrEqual(fragment?.utf8.count ?? .max, ClipCutName.maxBytes)
    }

    // MARK: - stem

    func testTheCutEndsTheName() {
        XCTAssertEqual(ClipCutName.stem("Trump drill", cut: "1:13 to :55"), "Trump drill 1.13 to .55")
        XCTAssertEqual(ClipCutName.stem("Trump drill", cut: " "), "Trump drill")
    }

    func testTheNameIsShortenedSoTheCutSurvives() {
        let name = String(repeating: "é", count: 120) // 240 bytes
        let stem = ClipCutName.stem(name, cut: "1:13 to :55")
        XCTAssertLessThanOrEqual(stem.utf8.count, YtDlpService.maxStemBytes)
        XCTAssertTrue(stem.hasSuffix(" 1.13 to .55"))
    }

    // MARK: - baseStem

    func testTheRowsCutComesOffTheName() {
        XCTAssertEqual(ClipCutName.baseStem("Trump drill 1.13 to .55", cut: "1:13 to :55"), "Trump drill")
    }

    func testANameWithoutTheCutIsLeftAlone() {
        XCTAssertEqual(ClipCutName.baseStem("Trump drill", cut: "1:13 to :55"), "Trump drill")
        XCTAssertEqual(ClipCutName.baseStem("Trump drill 1.13 to .55", cut: ""), "Trump drill 1.13 to .55")
        XCTAssertEqual(ClipCutName.baseStem("Trump drill1.13 to .55", cut: "1:13 to :55"),
                       "Trump drill1.13 to .55", "only a cut set off by a space is the cut")
    }

    // MARK: - YtDlpService.prefix

    func testPrefixCutsOnACharacterBoundary() {
        XCTAssertEqual(YtDlpService.prefix(of: "abcé", utf8Bytes: 4), "abc", "é is two bytes")
        XCTAssertEqual(YtDlpService.prefix(of: "abcé", utf8Bytes: 5), "abcé")
        XCTAssertEqual(YtDlpService.prefix(of: "abc", utf8Bytes: 0), "")
    }
}
