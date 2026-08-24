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
    ) -> ClipNotesFile.Record {
        ClipNotesFile.Record(filename: filename, notes: notes, timestamp: timestamp, sourceURL: url)
    }

    // MARK: - Naming

    func testTheFileIsNamedAfterTheSession() {
        XCTAssertEqual(file.lastPathComponent, "HT_0379 2026-08-24.txt")
    }

    // MARK: - Shape

    func testClipsAreSeparatedByARule() {
        let text = SessionNotesFile.render([
            record("A.m4a", notes: "TRUMP — one", timestamp: ":30 to :12", url: "https://a"),
            record(notes: "MAMDANI — two", url: "https://b"),
        ])
        XCTAssertEqual(text, """
        A.m4a

        TRUMP — one

        :30 to :12

        https://a

        ---

        MAMDANI — two

        https://b

        """)
    }

    func testRenderAndParseRoundTrip() {
        let records = [
            record("A.m4a", notes: "TRUMP — one\n\nscratch", timestamp: "1:13 to :55", url: "https://a"),
            record(notes: "MAMDANI — two", url: "https://b"),
        ]
        XCTAssertEqual(SessionNotesFile.parse(SessionNotesFile.render(records)), records)
    }

    func testAnEmptyFileParsesToNothing() {
        XCTAssertTrue(SessionNotesFile.parse("").isEmpty)
        XCTAssertTrue(SessionNotesFile.parse("\n---\n\n").isEmpty)
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

    // MARK: - Folding in the per-clip files that came before

    /// A pre-existing sidecar: its own folder, its own text file.
    @discardableResult
    private func makeSidecar(_ stem: String, notes: String, url: String) throws -> URL {
        let dir = folder.appendingPathComponent(stem, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let audio = dir.appendingPathComponent("\(stem).m4a")
        try Data("audio".utf8).write(to: audio)
        try ClipNotesFile.write(notes: notes, sourceURL: url, forAudioFile: audio)
        return audio
    }

    func testSidecarsAreFoldedIntoTheSessionFile() throws {
        try makeSidecar("Alpha", notes: "TRUMP — one", url: "https://a")
        try makeSidecar("Beta", notes: "MAMDANI — two", url: "https://b")

        let adopted = try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)
        XCTAssertEqual(adopted, 2)
        XCTAssertEqual(
            Set(SessionNotesFile.read(at: file).map(\.notes)),
            ["TRUMP — one", "MAMDANI — two"]
        )
    }

    func testFoldingInTwiceDoesNotDuplicate() throws {
        try makeSidecar("Alpha", notes: "TRUMP — one", url: "https://a")
        try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)
        let second = try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)

        XCTAssertEqual(second, 0)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 1)
    }

    func testTheSessionFileIsNotFoldedIntoItself() throws {
        try SessionNotesFile.upsert(record(notes: "already here", url: "https://a"), at: file)
        let adopted = try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)
        XCTAssertEqual(adopted, 0)
        XCTAssertEqual(SessionNotesFile.read(at: file).count, 1)
    }

    func testTheOriginalSidecarsAreLeftOnDisk() throws {
        let audio = try makeSidecar("Alpha", notes: "one", url: "https://a")
        try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)
        let sidecar = audio.deletingLastPathComponent().appendingPathComponent("Alpha.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path),
                      "migration must not delete the user's files")
    }
    // MARK: - The files a real session already holds

    /// Four clips as they actually sat on disk before the session file existed:
    /// different element orders, a cut written inline, and one file whose
    /// source URL had been lost during hand-consolidation.
    func testRealWorldSidecarsFoldInWithTheirCutsReadCorrectly() throws {
        let bodies: [(String, String)] = [
            ("Darlene", """
            Aaron_Rupar_-_Darlene_Graham_bumbled.m4a
            Darlene Graham — just bumbled through one of the worst responses to a question

            :40 to :14
            https://x.com/atrupar/status/2089911556301550045?s=43

            """),
            ("Mamdani", """
            Mamdani.m4a
            Mamdani — :05 to end
            https://x.com/atrupar/status/2091901792632062410?s=43

            """),
            ("Reagan", """
            Republicans_against_Trump_-_Reagan.m4a
            Reagan – a message for MAGA as Trump escalates the trade war with Canada — 1:13 to :55

            “We should beware of the demagogues who are willing to declare a trade war
            https://x.com/rpsagainsttrump/status/2091894948001903098?s=43

            """),
        ]
        for (stem, body) in bodies {
            let dir = folder.appendingPathComponent(stem, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: dir.appendingPathComponent("\(stem).txt"))
        }

        XCTAssertEqual(try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file), 3)
        let records = SessionNotesFile.read(at: file)

        let darlene = try XCTUnwrap(records.first { $0.sourceURL.contains("2089911556") })
        XCTAssertEqual(darlene.timestamp, ":40 to :14", "a cut on its own line is lifted out")
        XCTAssertTrue(darlene.notes.hasPrefix("Darlene Graham — just bumbled"))

        let mamdani = try XCTUnwrap(records.first { $0.sourceURL.contains("2091901792") })
        XCTAssertEqual(mamdani.timestamp, "", "a cut written inside the sentence stays in it")
        XCTAssertEqual(mamdani.notes, "Mamdani — :05 to end")

        let reagan = try XCTUnwrap(records.first { $0.sourceURL.contains("2091894948") })
        XCTAssertEqual(reagan.timestamp, "", "a trailing quotation is not a cut")
        XCTAssertTrue(reagan.notes.contains("demagogues"))
    }

    /// One of the real files had lost its source URL. It still folds in, but
    /// the last line it does have is taken for the source — worth pinning so
    /// the behaviour is known rather than discovered.
    func testASidecarMissingItsURLTakesItsLastLineAsTheSource() throws {
        let dir = folder.appendingPathComponent("Trump", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        TRUMP — "I should be at 100 percent on the economy"

        AUDIENCE: 😬

        :46 to :17
        """.utf8).write(to: dir.appendingPathComponent("Trump.txt"))

        try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file)
        let record = try XCTUnwrap(SessionNotesFile.read(at: file).first)
        XCTAssertEqual(record.sourceURL, ":46 to :17")
        XCTAssertEqual(record.notes, "TRUMP — \"I should be at 100 percent on the economy\"\n\nAUDIENCE: 😬")
    }
}
