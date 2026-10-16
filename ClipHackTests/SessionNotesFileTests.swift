import XCTest
@testable import ClipHackKit

@MainActor
final class SessionNotesFileTests: XCTestCase {

    private var folder: URL!
    private var file: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionnotes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = SessionNotesFile.url(inClipsFolder: folder, title: "HT_0379 2026-08-24")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func record(_ filename: String, cut: String = "", url: String = "") -> ClipRecord {
        ClipRecord(filename: filename, timestamp: cut, sourceURL: url)
    }

    // MARK: - Naming

    func testTheFileIsNamedAfterTheSession() {
        XCTAssertEqual(file.lastPathComponent, "HT_0379 2026-08-24.txt")
    }

    // MARK: - Shape

    /// Each clip's file name flush left, its cut under it, then its link.
    func testTheFileIsOneBlockPerClip() {
        let text = SessionNotesFile.render([
            record("CSPAN_-_Trump.m4a", url: "https://x.com/cspan/status/2109039198422405195?s=43"),
            record("This_Week_-_Hamilton 1.23 to .52.m4a", cut: "1:23 to :52",
                   url: "https://x.com/thisweekabc/status/2109318964635730038?s=43"),
        ])
        XCTAssertEqual(text, """
        CSPAN_-_Trump.m4a
            https://x.com/cspan/status/2109039198422405195

        This_Week_-_Hamilton 1.23 to .52.m4a
            CUT  1:23 to :52
            https://x.com/thisweekabc/status/2109318964635730038

        """, "X links are written without their tracking query")
    }

    func testRenderAndParseRoundTrip() {
        let records = [
            record("A 1.13 to .55.m4a", cut: "1:13 to :55", url: "https://a"),
            record("B.m4a", url: "https://b"),
            record("Added from disk 1.30 to end.wav", cut: "1:30 to end"),
        ]
        XCTAssertEqual(SessionNotesFile.parse(SessionNotesFile.render(records)), records)
    }

    /// A cut that starts with its own colon keeps it.
    func testACutStartingWithAColonKeepsIt() {
        let records = SessionNotesFile.parse("A.m4a\n    CUT  :18 to end\n    https://a\n")
        XCTAssertEqual(records, [record("A.m4a", cut: ":18 to end", url: "https://a")])
    }

    func testAnEmptyFileParsesToNothing() {
        XCTAssertTrue(SessionNotesFile.parse("").isEmpty)
        XCTAssertTrue(SessionNotesFile.parse("\n\n").isEmpty)
    }

    /// Only what ClipHack writes is read; a stray line under a clip is skipped.
    func testLinesClipHackDoesNotWriteAreSkipped() {
        let records = SessionNotesFile.parse("    stray\nA.m4a\n    something typed\n    https://a\n")
        XCTAssertEqual(records, [record("A.m4a", url: "https://a")])
    }

    // MARK: - Maintained, not appended

    func testUpsertAppendsANewClip() throws {
        try SessionNotesFile.upsert(record("One.m4a", url: "https://a"), at: file)
        try SessionNotesFile.upsert(record("Two.m4a", url: "https://b"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["One.m4a", "Two.m4a"])
    }

    func testUpsertReplacesTheSameClipRatherThanStackingIt() throws {
        try SessionNotesFile.upsert(record("First take.m4a", url: "https://a"), at: file)
        try SessionNotesFile.upsert(record("Second take.m4a", url: "https://a"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["Second take.m4a"])
    }

    func testAnXPostIsTheSameClipDespiteTrackingParams() throws {
        let base = "https://x.com/acyn/status/2109406640567161167"
        try SessionNotesFile.upsert(record("First.m4a", url: base), at: file)
        try SessionNotesFile.upsert(record("Second.m4a", url: base + "?s=43"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["Second.m4a"])
    }

    func testDifferentYouTubeVideosAreNotTheSameClip() throws {
        try SessionNotesFile.upsert(record("One.m4a", url: "https://youtube.com/watch?v=aaa"), at: file)
        try SessionNotesFile.upsert(record("Two.m4a", url: "https://youtube.com/watch?v=bbb"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 2)
    }

    func testWritingNothingRemovesTheFile() throws {
        try SessionNotesFile.upsert(record("One.m4a", url: "https://a"), at: file)
        try SessionNotesFile.write([], to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Cuts

    func testACutIsSetOnADownloadByItsLink() throws {
        try SessionNotesFile.upsert(record("Old name.m4a", url: "https://x.com/acyn/status/2109406640567161167"), at: file)
        try SessionNotesFile.setCut(":18 to end", filename: "Renamed.m4a", source: "https://x.com/acyn/status/2109406640567161167?s=43", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.timestamp), [":18 to end"], "found by its link despite the rename")
    }

    func testADownloadFoundByItsLinkTakesItsNewName() throws {
        try SessionNotesFile.upsert(record("Rupar.m4a", url: "https://x.com/acyn/status/2109406640567161167"), at: file)
        try SessionNotesFile.setCut(":18 to end", filename: "Rupar.m4a", renamedTo: "Rupar .18 to end.m4a",
                                    source: "https://x.com/acyn/status/2109406640567161167", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["Rupar .18 to end.m4a"])
    }

    /// A clip added from disk has a block only once it has a cut, under the
    /// name its file was renamed to.
    func testACutForAClipAddedFromDiskListsItByItsNewName() throws {
        try SessionNotesFile.setCut("to :03", filename: "Collins.wav", renamedTo: "Collins to .03.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file), [record("Collins to .03.wav", cut: "to :03")])
    }

    func testAnEmptyCutOnAnUnlistedClipAddsNothing() throws {
        try SessionNotesFile.setCut("", filename: "Nothing.wav", at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// Without its cut, a clip added from disk has nothing left to record.
    func testRemovingTheCutOfAClipAddedFromDiskRemovesItsBlock() throws {
        try SessionNotesFile.upsert(record("Download.m4a", url: "https://a"), at: file)
        try SessionNotesFile.setCut("1:13 to :55", filename: "A.wav", renamedTo: "A 1.13 to .55.wav", at: file)
        try SessionNotesFile.setCut("  ", filename: "A 1.13 to .55.wav", renamedTo: "A.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file), [record("Download.m4a", url: "https://a")])
    }

    /// A download keeps its block without a cut: its link is what a second
    /// paste of it is matched on.
    func testRemovingADownloadsCutKeepsItsBlock() throws {
        try SessionNotesFile.upsert(record("A 1.13 to .55.m4a", cut: "1:13 to :55", url: "https://a"), at: file)
        try SessionNotesFile.setCut("", filename: "A 1.13 to .55.m4a", renamedTo: "A.m4a", source: "https://a", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file), [record("A.m4a", url: "https://a")])
    }
}
