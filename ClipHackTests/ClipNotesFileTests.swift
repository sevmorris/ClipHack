import XCTest
@testable import ClipHackKit

@MainActor
final class ClipNotesFileTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipnotes-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Naming

    func testSidecarTakesTheAudioFileStem() {
        XCTAssertEqual(ClipNotesFile.filename(forAudioFile: "Some_Title.m4a"), "Some_Title.txt")
        XCTAssertEqual(ClipNotesFile.filename(forAudioFile: "Clip.with.dots.opus"), "Clip.with.dots.txt")
    }

    func testExtensionlessNameStillGetsATxtSidecar() {
        XCTAssertEqual(ClipNotesFile.filename(forAudioFile: "Untitled"), "Untitled.txt")
    }

    // MARK: - Body format

    func testEveryElementIsSeparatedByABlankLine() {
        XCTAssertEqual(
            ClipNotesFile.body(
                filename: "Clip.m4a",
                notes: "Trump — the quote",
                timestamp: "1:13 to :55",
                sourceURL: "https://example.com/watch?v=abc"
            ),
            "Clip.m4a\n\nTrump — the quote\n\n1:13 to :55\n\nhttps://example.com/watch?v=abc\n"
        )
    }

    func testAnOmittedFilenameLeavesNoGapAtTheTop() {
        XCTAssertEqual(
            ClipNotesFile.body(filename: "", notes: "Trump — the quote", sourceURL: "https://u"),
            "Trump — the quote\n\nhttps://u\n"
        )
    }

    func testEmptyElementsAreLeftOutRatherThanWrittenBlank() {
        // A blank line always means "next element", never "this one is empty".
        XCTAssertEqual(
            ClipNotesFile.body(filename: "Clip.m4a", notes: "", sourceURL: "https://u"),
            "Clip.m4a\n\nhttps://u\n"
        )
        XCTAssertEqual(
            ClipNotesFile.body(filename: "Clip.m4a", notes: "note", timestamp: "", sourceURL: "https://u"),
            "Clip.m4a\n\nnote\n\nhttps://u\n"
        )
    }

    func testMultilineNotesAreKeptVerbatim() {
        XCTAssertEqual(
            ClipNotesFile.body(filename: "Clip.m4a", notes: "line one\nline two", sourceURL: "https://u"),
            "Clip.m4a\n\nline one\nline two\n\nhttps://u\n"
        )
    }

    // MARK: - Writing

    func testWritePutsSidecarBesideTheAudioFile() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(notes: "the good part", sourceURL: "https://a", forAudioFile: audio)

        let sidecar = tempDir.appendingPathComponent("Title.txt")
        XCTAssertEqual(
            try String(contentsOf: sidecar, encoding: .utf8),
            "Title.m4a\n\nthe good part\n\nhttps://a\n"
        )
    }

    func testAHandNamedClipLeavesTheFilenameOut() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(
            notes: "Trump — the quote",
            timestamp: "1:13 to :55",
            sourceURL: "https://a",
            forAudioFile: audio,
            includeFilename: false
        )
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("Title.txt"), encoding: .utf8),
            "Trump — the quote\n\n1:13 to :55\n\nhttps://a\n"
        )
    }


    // MARK: - Reading back (notes survive the session)


    func testParseKeepsMultilineNotesIncludingBlankLines() {
        let record = ClipNotesFile.parse("Clip.m4a\nfirst para\n\nsecond para\nhttps://u\n\n")
        XCTAssertEqual(record?.notes, "first para\n\nsecond para")
        XCTAssertEqual(record?.sourceURL, "https://u")
    }

    func testParseHandlesEmptyNotes() {
        XCTAssertEqual(ClipNotesFile.parse("Clip.m4a\n\nhttps://u\n\n")?.notes, "")
    }

    func testParseRejectsJunk() {
        XCTAssertNil(ClipNotesFile.parse(""))
        XCTAssertNil(ClipNotesFile.parse("just one line\n"),
                     "a lone line that is not a URL must not read as a clip")
        XCTAssertNil(ClipNotesFile.parse("\n\n\n"))
    }

    func testAMissingFilenameIsNowAValidRecord() {
        // Hand-named clips write no filename line.
        let record = ClipNotesFile.parse("Trump — the quote\n\nhttps://u\n")
        XCTAssertEqual(record?.filename, "")
        XCTAssertEqual(record?.notes, "Trump — the quote")
        XCTAssertEqual(record?.sourceURL, "https://u")
    }

    // MARK: - Timestamps

    func testTimestampRoundTrips() {
        let text = ClipNotesFile.body(
            filename: "Clip.m4a", notes: "Trump — the quote",
            timestamp: "1:13 to :55", sourceURL: "https://u"
        )
        let record = ClipNotesFile.parse(text)
        XCTAssertEqual(record?.timestamp, "1:13 to :55")
        XCTAssertEqual(record?.notes, "Trump — the quote", "the cut must not bleed into the notes")
    }

    func testNotesEndingInProseAreNotMistakenForATimestamp() {
        let record = ClipNotesFile.parse("Clip.m4a\n\nfirst para\n\nsecond para\n\nhttps://u\n")
        XCTAssertEqual(record?.timestamp, "")
        XCTAssertEqual(record?.notes, "first para\n\nsecond para")
    }

    func testTimestampShapes() {
        for good in ["1:13 to :55", ":30 to :12", "To :17", "0:05", "1:13-2:00", "to 1:02"] {
            XCTAssertTrue(ClipNotesFile.isTimestamp(good), good)
        }
        for bad in ["Trump — said it", "second para", "100", "AUDIENCE: 😬", ""] {
            XCTAssertFalse(ClipNotesFile.isTimestamp(bad), bad)
        }
    }

    func testAPreExistingSidecarStillParsesAndItsCutIsLifted() {
        // The shape ClipHack wrote before this change: single lines, no blanks
        // between elements, and the cut at the end of the notes.
        let record = ClipNotesFile.parse(
            "Aaron_Rupar_TRUMP.m4a\nTRUMP — \"the quote\"\n\nAUDIENCE: 😬\n\nTo :17\nhttps://x.com/atrupar/status/2090948085333504072\n\n"
        )
        XCTAssertEqual(record?.filename, "Aaron_Rupar_TRUMP.m4a")
        XCTAssertEqual(record?.notes, "TRUMP — \"the quote\"\n\nAUDIENCE: 😬")
        XCTAssertEqual(record?.timestamp, "To :17")
        XCTAssertEqual(record?.sourceURL, "https://x.com/atrupar/status/2090948085333504072")
    }


    // MARK: - Finding an already-downloaded clip

    /// Directory scans hand back `/private/var/…` where the test built
    /// `/var/…`, so compare the file each URL resolves to, not its spelling.
    private func assertSameFile(
        _ lhs: URL?, _ rhs: URL?, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            lhs?.resolvingSymlinksInPath().path,
            rhs?.resolvingSymlinksInPath().path,
            message, file: file, line: line
        )
    }

    /// Mirrors a real download: a clip folder holding audio plus its sidecar.
    @discardableResult
    private func makeClip(_ stem: String, source: String, notes: String = "") throws -> URL {
        let folder = tempDir.appendingPathComponent(stem, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("\(stem).m4a")
        try Data("audio".utf8).write(to: audio)
        try ClipNotesFile.write(notes: notes, sourceURL: source, forAudioFile: audio)
        return audio
    }







    func testSecondWriteReplacesRatherThanAppends() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(notes: "first", sourceURL: "https://a", forAudioFile: audio)
        try ClipNotesFile.write(notes: "second", sourceURL: "https://a", forAudioFile: audio)

        let sidecar = tempDir.appendingPathComponent("Title.txt")
        XCTAssertEqual(
            try String(contentsOf: sidecar, encoding: .utf8),
            "Title.m4a\n\nsecond\n\nhttps://a\n",
            "one clip per file — a re-download records what it was downloaded with"
        )
    }
    // MARK: - Reading a folder's worth of clips (the clip list panel)

    func testEntriesFindsEveryClipInTheFolder() throws {
        try makeClip("Alpha", source: "https://a", notes: "Trump — first")
        try makeClip("Beta", source: "https://b", notes: "Vance — second")
        try makeClip("Gamma", source: "https://c")

        let entries = ClipNotesFile.entries(in: tempDir)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(
            Set(entries.map(\.record.filename)),
            ["Alpha.m4a", "Beta.m4a", "Gamma.m4a"]
        )
        XCTAssertTrue(entries.allSatisfy { $0.audio != nil })
    }

    func testEntriesKeepsAClipWhoseAudioIsGone() throws {
        let audio = try makeClip("Alpha", source: "https://a", notes: "Trump — said it")
        try FileManager.default.removeItem(at: audio)

        let entries = ClipNotesFile.entries(in: tempDir)
        XCTAssertEqual(entries.count, 1, "the list has to survive the audio being cleaned up")
        XCTAssertEqual(entries.first?.record.notes, "Trump — said it")
        XCTAssertNil(entries.first?.audio, "and has to say the audio is gone")
    }

    func testEntriesReadInTheOrderClipsWereAdded() throws {
        // Names deliberately reverse-alphabetical against their write order, so
        // an alphabetical sort would fail this.
        for (stem, day) in [("Zulu", 1), ("Mike", 2), ("Alpha", 3)] {
            try makeClip(stem, source: "https://\(stem)")
            let sidecar = tempDir
                .appendingPathComponent(stem, isDirectory: true)
                .appendingPathComponent("\(stem).txt")
            try FileManager.default.setAttributes(
                [.creationDate: Date(timeIntervalSince1970: TimeInterval(day) * 86_400)],
                ofItemAtPath: sidecar.path
            )
        }

        XCTAssertEqual(
            ClipNotesFile.entries(in: tempDir).map(\.record.filename),
            ["Zulu.m4a", "Mike.m4a", "Alpha.m4a"]
        )
    }

    func testEntriesIsEmptyForAFolderWithNoClips() {
        XCTAssertTrue(ClipNotesFile.entries(in: tempDir).isEmpty)
    }

    // MARK: - Editing a clip's notes after the fact


    // MARK: - End to end: a folder of clips becomes the list

    func testFolderOfClipsExportsAsTheNumberedList() throws {
        let clips = [
            ("Clip1", "Trump — traveled to South Dakota to read a red scare speech\n:30 to :12"),
            ("Clip2", "JD Vance — said the quiet part out loud"),
            ("Clip3", ""),   // downloaded but never written up
        ]
        for (day, clip) in clips.enumerated() {
            try makeClip(clip.0, source: "https://\(clip.0)", notes: clip.1)
            let sidecar = tempDir
                .appendingPathComponent(clip.0, isDirectory: true)
                .appendingPathComponent("\(clip.0).txt")
            try FileManager.default.setAttributes(
                [.creationDate: Date(timeIntervalSince1970: TimeInterval(day + 1) * 86_400)],
                ofItemAtPath: sidecar.path
            )
        }

        let entries = ClipNotesFile.entries(in: tempDir).map {
            ClipListEntry.parse(notes: $0.record.notes)
        }

        XCTAssertEqual(
            ClipListEntry.numberedList(entries),
            """
            1) TRUMP traveled to South Dakota to read a red scare speech
            2) JD VANCE said the quiet part out loud
            """,
            "timings stay out of the list, an unwritten clip takes no number"
        )
    }
    /// The exact shape of a hand-written block: no filename line, a blank line
    /// inside the notes, the cut on its own line, then the source URL.
    func testHandWrittenBlockWithNoFilenameParsesEveryPart() {
        let record = ClipNotesFile.parse("""
        TRUMP — "I should be at 100 percent on the economy"

        AUDIENCE: 😬

        :46 to :17

        https://x.com/atrupar/status/2090948085333504072?s=43
        """)
        XCTAssertEqual(record?.filename, "")
        XCTAssertEqual(record?.notes, "TRUMP — \"I should be at 100 percent on the economy\"\n\nAUDIENCE: 😬")
        XCTAssertEqual(record?.timestamp, ":46 to :17")
        XCTAssertEqual(record?.sourceURL, "https://x.com/atrupar/status/2090948085333504072?s=43")
    }
}
