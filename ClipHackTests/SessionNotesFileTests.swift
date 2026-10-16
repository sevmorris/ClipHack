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

    private func record(
        _ filename: String = "", notes: String, timestamp: String = "", url: String
    ) -> ClipRecord {
        ClipRecord(filename: filename, notes: notes, timestamp: timestamp, sourceURL: url)
    }

    // MARK: - Naming

    func testTheFileIsNamedAfterTheSession() {
        XCTAssertEqual(file.lastPathComponent, "HT_0379 2026-08-24.txt")
    }

    // MARK: - Shape

    /// Laid out to work from while editing: each clip's file name flush left
    /// with its cut right under it and the link last, and nothing above the
    /// first clip.
    func testTheFileIsOneBlockPerClip() {
        let text = SessionNotesFile.render([
            record("CSPAN_-_Trump.m4a", notes: "", url: "https://x.com/cspan/status/2109039198422405195?s=43"),
            record("This_Week_-_Hamilton.m4a", notes: "", timestamp: "1:23 to :52",
                   url: "https://x.com/thisweekabc/status/2109318964635730038?s=43"),
        ])
        XCTAssertEqual(text, """
        CSPAN_-_Trump.m4a
            https://x.com/cspan/status/2109039198422405195

        This_Week_-_Hamilton.m4a
            CUT  1:23 to :52
            https://x.com/thisweekabc/status/2109318964635730038

        """)
    }

    func testOldNotesSitBetweenTheCutAndTheLink() {
        let text = SessionNotesFile.render([
            record("A.m4a", notes: "TRUMP — one", timestamp: ":30 to :12", url: "https://a"),
            record(notes: "MAMDANI — two", url: "https://b"),
        ])
        XCTAssertEqual(text, """
        A.m4a
            CUT  :30 to :12
            TRUMP — one
            https://a

        (no file name)
            MAMDANI — two
            https://b

        """)
    }

    /// No count line: the file is already named after the session, and
    /// nothing reads the counts.
    func testTheWrittenFileStartsWithItsFirstClip() throws {
        try SessionNotesFile.write([record("A.m4a", notes: "", url: "https://a")], to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "A.m4a\n    https://a\n")
    }

    func testXLinksAreWrittenWithoutTheirTrackingQuery() {
        XCTAssertEqual(
            SessionNotesFile.tidied("https://x.com/acyn/status/2109406640567161167?s=43"),
            "https://x.com/acyn/status/2109406640567161167"
        )
        XCTAssertEqual(
            SessionNotesFile.tidied("https://youtube.com/watch?v=aaa"),
            "https://youtube.com/watch?v=aaa",
            "a YouTube video's id lives in its query"
        )
    }

    func testRenderAndParseRoundTrip() {
        let records = [
            record("A.m4a", notes: "TRUMP — one\n\nscratch", timestamp: "1:13 to :55", url: "https://a"),
            record(notes: "MAMDANI — two", url: "https://b"),
        ]
        XCTAssertEqual(SessionNotesFile.parse(SessionNotesFile.render(records)), records)
    }

    /// The shape a download writes now: filename, cut, source — no notes.
    func testABlockWithNoNotesRoundTrips() {
        let records = [
            record("A.m4a", notes: "", timestamp: "1:13 to :55", url: "https://a"),
            record("B.m4a", notes: "", url: "https://b"),
        ]
        XCTAssertEqual(SessionNotesFile.parse(SessionNotesFile.render(records)), records)
    }

    /// Text in an old block that doesn't read as a cut stays notes, and comes
    /// back as notes after a rewrite — which is why the file keeps every
    /// element it parses, not only the ones a download writes.
    func testNotesThatAreNotACutSurviveARewrite() {
        let records = SessionNotesFile.parse("A.m4a\n    first twenty seconds\n    https://a\n")
        XCTAssertEqual(records.first?.notes, "first twenty seconds")
        XCTAssertEqual(SessionNotesFile.parse(SessionNotesFile.render(records)), records)
    }

    /// The form the show uses most: an in point, then "end".
    func testACutToTheEndIsACut() {
        let old = SessionNotesFile.parse("A.m4a\n\n0:05 to end\n\nhttps://a\n")
        XCTAssertEqual(old.first?.timestamp, "0:05 to end")
        XCTAssertEqual(old.first?.notes, "")
    }

    func testAnEmptyFileParsesToNothing() {
        XCTAssertTrue(SessionNotesFile.parse("").isEmpty)
        XCTAssertTrue(SessionNotesFile.parse("\n\n").isEmpty)
    }

    // MARK: - Reading what's on disk

    /// A cut typed into the file by hand, without the label or the indent.
    func testAHandTypedCutStillCounts() {
        let records = SessionNotesFile.parse("""
        A.m4a
            1:13 to :55
            https://a

        B.m4a
        :18 to end
            https://b

        """)
        XCTAssertEqual(records.map(\.timestamp), ["1:13 to :55", ":18 to end"])
        XCTAssertEqual(records.map(\.filename), ["A.m4a", "B.m4a"], "a cut never reads as the next clip")
    }

    func testNotesStartingWithCutAreNotACut() {
        let records = SessionNotesFile.parse("A.m4a\n    Cut the crap, he said\n    https://a\n")
        XCTAssertEqual(records.first?.timestamp, "")
        XCTAssertEqual(records.first?.notes, "Cut the crap, he said")
    }

    // MARK: - Maintained, not appended

    func testUpsertAppendsANewClip() throws {
        try SessionNotesFile.upsert(record(notes: "one", url: "https://a"), at: file)
        try SessionNotesFile.upsert(record(notes: "two", url: "https://b"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.notes), ["one", "two"])
    }

    func testUpsertReplacesTheSameClipRatherThanStackingIt() throws {
        try SessionNotesFile.upsert(record(notes: "first take", url: "https://a"), at: file)
        try SessionNotesFile.upsert(record(notes: "second take", url: "https://a"), at: file)

        let notes = SessionNotesFile.read(at: file).map(\.notes)
        XCTAssertEqual(notes, ["second take"], "a re-download must not leave a stale block behind")
    }

    func testAnXPostIsTheSameClipDespiteTrackingParams() throws {
        let base = "https://x.com/atrupar/status/2090948085333504072"
        try SessionNotesFile.upsert(record(notes: "first", url: base), at: file)
        try SessionNotesFile.upsert(record(notes: "second", url: base + "?s=43"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 1)
    }

    func testDifferentYouTubeVideosAreNotTheSameClip() throws {
        try SessionNotesFile.upsert(record(notes: "one", url: "https://youtube.com/watch?v=aaa"), at: file)
        try SessionNotesFile.upsert(record(notes: "two", url: "https://youtube.com/watch?v=bbb"), at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 2, "the video id lives in the query")
    }

    func testWritingNothingRemovesTheFile() throws {
        try SessionNotesFile.upsert(record(notes: "one", url: "https://a"), at: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try SessionNotesFile.write([], to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "an emptied session leaves no stale file")
    }

    // MARK: - Clips added by hand, and their cuts

    func testAFileAddedByHandIsListedByName() throws {
        XCTAssertEqual(try SessionNotesFile.recordAddedFiles(named: ["Talarico.wav"], at: file), 1)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Talarico.wav\n")
        XCTAssertEqual(SessionNotesFile.read(at: file), [record("Talarico.wav", notes: "", url: "")])
    }

    func testAFileAlreadyListedIsNotAddedAgain() throws {
        try SessionNotesFile.upsert(record("Rupar.m4a", notes: "", url: "https://x.com/acyn/status/2109406640567161167"), at: file)
        XCTAssertEqual(try SessionNotesFile.recordAddedFiles(named: ["Rupar.m4a", "Rupar.m4a"], at: file), 0)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 1)
    }

    func testACutIsSetOnADownloadByItsLink() throws {
        try SessionNotesFile.upsert(record("Old name.m4a", notes: "", url: "https://x.com/acyn/status/2109406640567161167"), at: file)
        try SessionNotesFile.setCut(":18 to end", filename: "Renamed.m4a", source: "https://x.com/acyn/status/2109406640567161167?s=43", at: file)
        let records = SessionNotesFile.read(at: file)
        XCTAssertEqual(records.map(\.timestamp), [":18 to end"], "found by its link despite the rename")
    }

    func testARenamedClipsBlockTakesItsNewName() throws {
        try SessionNotesFile.recordAddedFiles(named: ["Talarico.wav"], at: file)
        try SessionNotesFile.setCut("1:23 to :52", filename: "Talarico.wav",
                                    renamedTo: "Talarico 1.23 to .52.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file),
                       [record("Talarico 1.23 to .52.wav", notes: "", timestamp: "1:23 to :52", url: "")])
    }

    func testADownloadFoundByItsLinkTakesItsNewName() throws {
        try SessionNotesFile.upsert(record("Rupar.m4a", notes: "", url: "https://x.com/acyn/status/2109406640567161167"), at: file)
        try SessionNotesFile.setCut(":18 to end", filename: "Rupar.m4a", renamedTo: "Rupar .18 to end.m4a",
                                    source: "https://x.com/acyn/status/2109406640567161167", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["Rupar .18 to end.m4a"])
    }

    func testACutForAnUnlistedRenamedFileListsItByItsNewName() throws {
        try SessionNotesFile.setCut("to :03", filename: "Collins.wav", renamedTo: "Collins to .03.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file).map(\.filename), ["Collins to .03.wav"])
    }

    func testACutIsSetOnAFileAddedByHandByItsName() throws {
        try SessionNotesFile.recordAddedFiles(named: ["Talarico.wav"], at: file)
        try SessionNotesFile.setCut("1:23 to :52", filename: "Talarico.wav", at: file)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8)
            .contains("Talarico.wav\n    CUT  1:23 to :52\n"))
        XCTAssertEqual(SessionNotesFile.read(at: file).first?.timestamp, "1:23 to :52")
    }

    func testACutForAnUnlistedFileListsIt() throws {
        try SessionNotesFile.setCut("to :03", filename: "Collins.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file),
                       [record("Collins.wav", notes: "", timestamp: "to :03", url: "")])
    }

    func testAnEmptyCutRemovesItAndAddsNothing() throws {
        try SessionNotesFile.setCut("", filename: "Nothing.wav", at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try SessionNotesFile.setCut("1:13 to :55", filename: "A.wav", at: file)
        try SessionNotesFile.setCut("  ", filename: "A.wav", at: file)
        XCTAssertEqual(SessionNotesFile.read(at: file), [record("A.wav", notes: "", url: "")])
    }
}
