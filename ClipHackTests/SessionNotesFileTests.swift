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
        let records = SessionNotesFile.parse("A.m4a\n\nfirst twenty seconds\n\nhttps://a\n")
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
        XCTAssertTrue(SessionNotesFile.parse("\n---\n\n").isEmpty)
        XCTAssertTrue(SessionNotesFile.parse("HT_0385 2026-10-13 · 0 clips\n").isEmpty)
    }

    // MARK: - Reading what's on disk

    /// Every session file written before this layout.
    func testAFileInTheEarlierLayoutStillReads() {
        let records = SessionNotesFile.parse("""
        This_Week_-_Hamilton.m4a

        1:23 to :52

        https://x.com/thisweekabc/status/2109318964635730038?s=43

        ---

        That_Gay_Guy_-_Collins.m4a

        to :03

        https://x.com/gayguycandleco/status/2107636372991541253?s=43

        """)
        XCTAssertEqual(records.map(\.filename), ["This_Week_-_Hamilton.m4a", "That_Gay_Guy_-_Collins.m4a"])
        XCTAssertEqual(records.map(\.timestamp), ["1:23 to :52", "to :03"])
    }

    /// One clip in the earlier layout has no `---` rule to give it away.
    func testAOneClipFileInTheEarlierLayoutStillReads() {
        let records = SessionNotesFile.parse("A.m4a\n\n1:13 to :55\n\nhttps://a\n")
        XCTAssertEqual(records, [record("A.m4a", notes: "", timestamp: "1:13 to :55", url: "https://a")])
    }

    /// 1.29.0 headed the file with counts, here ones that no longer match the
    /// clips below them. The line is not read as a clip, and the next save
    /// leaves it out.
    func testA129FileLosesItsCountLineTheNextTimeItIsSaved() throws {
        try Data("""
        HT_0379 2026-08-24 · 2 clips · 2 cuts

        CSPAN_-_Trump.m4a
            https://x.com/cspan/status/2109039198422405195

        Talarico.wav

        """.utf8).write(to: file)
        XCTAssertEqual(
            SessionNotesFile.read(at: file),
            [record("CSPAN_-_Trump.m4a", notes: "", url: "https://x.com/cspan/status/2109039198422405195"),
             record("Talarico.wav", notes: "", url: "")],
            "the count line is not read as a clip"
        )

        try SessionNotesFile.recordAddedFiles(named: ["Collins.wav"], at: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), """
        CSPAN_-_Trump.m4a
            https://x.com/cspan/status/2109039198422405195

        Talarico.wav

        Collins.wav

        """)
    }

    /// Clips added by hand have nothing indented, so in a 1.29.0 file of only
    /// those the count line is all that marks the layout. Saved once, the file
    /// reads the same without it.
    func testA129FileOfNamesOnlyReadsTheSameOnceSaved() throws {
        try Data("HT_0379 2026-08-24 · 2 clips\n\nA.wav\n\nB.wav\n".utf8).write(to: file)
        let records = SessionNotesFile.read(at: file)
        XCTAssertEqual(records.map(\.filename), ["A.wav", "B.wav"])

        try SessionNotesFile.write(records, to: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "A.wav\n\nB.wav\n")
        XCTAssertEqual(SessionNotesFile.read(at: file), records)
    }

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

    /// Clips added by hand have no links, so a file of only those has nothing
    /// indented and no rule; it must not be taken for the earlier layout.
    func testAFileOfNamesOnlyIsNotTakenForTheEarlierLayout() {
        let records = SessionNotesFile.parse("A.wav\n\nB.wav\n")
        XCTAssertEqual(records.map(\.filename), ["A.wav", "B.wav"])
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

    /// Hacks on Tap keeps its running order and transcripts in `clips/docs/`.
    /// Both parse as records, but neither is a clip: folding them in pasted the
    /// whole clip list into the session file, again each time it grew.
    func testOtherTextFilesInTheClipsFolderAreNotFoldedIn() throws {
        let docs = folder.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("""
        OHIO SENATE
        1 - ANTI-HUSTED AD - blocked Epstein files release

        TRUMP
        2 - TRUMP - blame me if we lose
        """.utf8).write(to: docs.appendingPathComponent("Clip_List.txt"))
        try Data("""
        1 - ANTI-HUSTED AD - blocked Epstein files release
        Seen these ads? They're a complete lie.

        2 - TRUMP - blame me if we lose
        If we don't win the midterms, they're going to blame me.
        """.utf8).write(to: docs.appendingPathComponent("All_Transcriptions.txt"))

        XCTAssertEqual(try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file), 0)
        XCTAssertTrue(SessionNotesFile.read(at: file).isEmpty)
    }

    /// Skipping those must not shut out a real sidecar that lost its link but
    /// still sits beside its audio in the clips folder itself.
    func testASidecarBesideItsAudioFoldsInWithoutALink() throws {
        try Data("audio".utf8).write(to: folder.appendingPathComponent("Rupar.m4a"))
        try Data("""
        RUPAR — "a line worth keeping"

        :12 to end
        """.utf8).write(to: folder.appendingPathComponent("Rupar.txt"))

        XCTAssertEqual(try SessionNotesFile.adoptSidecars(in: folder, sessionFile: file), 1)
    }
}
