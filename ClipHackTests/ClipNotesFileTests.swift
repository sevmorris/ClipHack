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

    // MARK: - Body format (kept identical to the clip list this replaced)

    func testBodyHasThreeLinesAndTrailingBlank() {
        XCTAssertEqual(
            ClipNotesFile.body(
                filename: "Clip.m4a",
                notes: ":30 to :12",
                sourceURL: "https://example.com/watch?v=abc"
            ),
            "Clip.m4a\n:30 to :12\nhttps://example.com/watch?v=abc\n\n"
        )
    }

    func testEmptyNotesStayABlankLine() {
        XCTAssertEqual(
            ClipNotesFile.body(filename: "Clip.m4a", notes: "", sourceURL: "https://u"),
            "Clip.m4a\n\nhttps://u\n\n"
        )
    }

    func testMultilineNotesAreKeptVerbatim() {
        XCTAssertEqual(
            ClipNotesFile.body(filename: "Clip.m4a", notes: "line one\nline two", sourceURL: "https://u"),
            "Clip.m4a\nline one\nline two\nhttps://u\n\n"
        )
    }

    // MARK: - Writing

    func testWritePutsSidecarBesideTheAudioFile() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(notes: "the good part", sourceURL: "https://a", forAudioFile: audio)

        let sidecar = tempDir.appendingPathComponent("Title.txt")
        XCTAssertEqual(
            try String(contentsOf: sidecar, encoding: .utf8),
            "Title.m4a\nthe good part\nhttps://a\n\n"
        )
    }

    // MARK: - Reading back (notes survive the session)

    func testRoundTripRestoresNotesAndSource() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(notes: "Vance on tariffs", sourceURL: "https://x.com/a/status/12", forAudioFile: audio)

        let record = try XCTUnwrap(ClipNotesFile.read(forAudioFile: audio))
        XCTAssertEqual(record.filename, "Title.m4a")
        XCTAssertEqual(record.notes, "Vance on tariffs")
        XCTAssertEqual(record.sourceURL, "https://x.com/a/status/12")
    }

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
        XCTAssertNil(ClipNotesFile.parse("just one line\n"))
        XCTAssertNil(ClipNotesFile.parse("\n\nhttps://u\n"), "a missing filename is not a record")
    }

    func testReadReturnsNilWhenThereIsNoSidecar() {
        XCTAssertNil(ClipNotesFile.read(forAudioFile: tempDir.appendingPathComponent("Nothing.m4a")))
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

    func testFindsClipDownloadedInAnEarlierSession() throws {
        let audio = try makeClip("Title", source: "https://youtube.com/watch?v=abc")
        try makeClip("Other", source: "https://youtube.com/watch?v=zzz")

        assertSameFile(
            ClipNotesFile.existingClip(forSourceURL: "https://youtube.com/watch?v=abc", in: tempDir),
            audio
        )
        XCTAssertNil(ClipNotesFile.existingClip(forSourceURL: "https://youtube.com/watch?v=new", in: tempDir))
    }

    func testXPostMatchesDespiteTrackingParams() throws {
        let audio = try makeClip("Post", source: "https://x.com/atrupar/status/2073253157933666426")

        assertSameFile(
            ClipNotesFile.existingClip(
                forSourceURL: "https://x.com/atrupar/status/2073253157933666426?s=46&t=xyz",
                in: tempDir
            ),
            audio,
            "the same post pasted with different params is the same clip"
        )
    }

    func testYouTubeVideoIDsAreNotTreatedAsInterchangeable() {
        XCTAssertFalse(
            ClipNotesFile.isSameSource(
                "https://youtube.com/watch?v=abc",
                "https://youtube.com/watch?v=different"
            ),
            "the query string carries the video id — it must not be ignored"
        )
    }

    func testDeletedClipDoesNotBlockRedownload() throws {
        let audio = try makeClip("Title", source: "https://a")
        try FileManager.default.removeItem(at: audio)   // show's over, files deleted

        XCTAssertNil(
            ClipNotesFile.existingClip(forSourceURL: "https://a", in: tempDir),
            "a leftover sidecar with no audio must not block downloading it again"
        )
    }

    func testRenamedClipIsStillFoundViaItsStem() throws {
        let audio = try makeClip("Title", source: "https://a")
        let renamed = audio.deletingLastPathComponent().appendingPathComponent("Title.opus")
        try FileManager.default.moveItem(at: audio, to: renamed)

        assertSameFile(ClipNotesFile.existingClip(forSourceURL: "https://a", in: tempDir), renamed)
    }

    func testFindsClipSittingLooseInTheDestination() throws {
        // A download from before per-clip folders, or one whose move fell back.
        let audio = tempDir.appendingPathComponent("Loose.m4a")
        try Data("audio".utf8).write(to: audio)
        try ClipNotesFile.write(notes: "", sourceURL: "https://loose", forAudioFile: audio)

        assertSameFile(ClipNotesFile.existingClip(forSourceURL: "https://loose", in: tempDir), audio)
    }

    func testSecondWriteReplacesRatherThanAppends() throws {
        let audio = tempDir.appendingPathComponent("Title.m4a")
        try ClipNotesFile.write(notes: "first", sourceURL: "https://a", forAudioFile: audio)
        try ClipNotesFile.write(notes: "second", sourceURL: "https://a", forAudioFile: audio)

        let sidecar = tempDir.appendingPathComponent("Title.txt")
        XCTAssertEqual(
            try String(contentsOf: sidecar, encoding: .utf8),
            "Title.m4a\nsecond\nhttps://a\n\n",
            "one clip per file — a re-download records what it was downloaded with"
        )
    }
}
