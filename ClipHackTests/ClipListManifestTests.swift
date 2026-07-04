import XCTest
@testable import ClipHack

@MainActor
final class ClipListManifestTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliplist-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 4
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Formatting

    func testManifestFilenameIsDateStamped() {
        XCTAssertEqual(
            ClipListManifest.manifestFilename(for: fixedDate()),
            "clip-list-2026-07-04.txt"
        )
    }

    func testEntryHasThreeLinesAndBlankSeparator() {
        XCTAssertEqual(
            ClipListManifest.entry(
                filename: "Clip.m4a",
                notes: ":30 to :12",
                sourceURL: "https://example.com/watch?v=abc"
            ),
            "Clip.m4a\n:30 to :12\nhttps://example.com/watch?v=abc\n\n"
        )
    }

    func testEmptyNotesStayABlankLine() {
        XCTAssertEqual(
            ClipListManifest.entry(filename: "Clip.m4a", notes: "", sourceURL: "https://u"),
            "Clip.m4a\n\nhttps://u\n\n"
        )
    }

    func testMultilineNotesAreKeptVerbatim() {
        let entry = ClipListManifest.entry(
            filename: "Clip.m4a",
            notes: "line one\nline two",
            sourceURL: "https://u"
        )
        XCTAssertEqual(entry, "Clip.m4a\nline one\nline two\nhttps://u\n\n")
    }

    // MARK: - Append vs create

    func testAppendCreatesManifestOnFirstWrite() throws {
        let entry = ClipListManifest.entry(filename: "A.m4a", notes: "", sourceURL: "https://a")
        try ClipListManifest.append(entry: entry, in: tempDir, date: fixedDate())

        let manifestURL = tempDir.appendingPathComponent("clip-list-2026-07-04.txt")
        XCTAssertEqual(try String(contentsOf: manifestURL, encoding: .utf8), entry)
    }

    func testSecondWriteAppendsToExistingManifest() throws {
        let first = ClipListManifest.entry(filename: "A.m4a", notes: "one", sourceURL: "https://a")
        let second = ClipListManifest.entry(filename: "B.m4a", notes: "two", sourceURL: "https://b")
        try ClipListManifest.append(entry: first, in: tempDir, date: fixedDate())
        try ClipListManifest.append(entry: second, in: tempDir, date: fixedDate())

        let manifestURL = tempDir.appendingPathComponent("clip-list-2026-07-04.txt")
        XCTAssertEqual(try String(contentsOf: manifestURL, encoding: .utf8), first + second)
    }
}
