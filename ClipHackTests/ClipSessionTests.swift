import XCTest
@testable import ClipHackKit

@MainActor
final class ClipSessionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipsession-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Mirrors the real layout: <root>/<title>/clips
    @discardableResult
    private func makeEpisode(_ title: String, withClipsFolder: Bool = true) throws -> URL {
        let folder = root.appendingPathComponent(title, isDirectory: true)
        let target = withClipsFolder
            ? folder.appendingPathComponent("clips", isDirectory: true)
            : folder
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Listing

    func testSessionsAreListedNewestFirst() throws {
        try makeEpisode("HT_0378 2026-08-10")
        try makeEpisode("HT_0380 2026-08-24")
        try makeEpisode("HT_0379 2026-08-17")

        XCTAssertEqual(
            ClipSessionStore.sessions(inRoot: root).map(\.title),
            ["HT_0380 2026-08-24", "HT_0379 2026-08-17", "HT_0378 2026-08-10"]
        )
    }

    func testSessionPointsAtItsClipsSubfolder() throws {
        let folder = try makeEpisode("HT_0379 2026-08-24")
        let session = try XCTUnwrap(ClipSessionStore.sessions(inRoot: root).first)
        XCTAssertEqual(session.folder.lastPathComponent, "HT_0379 2026-08-24")
        XCTAssertEqual(
            session.clipsFolder.standardizedFileURL.path,
            folder.appendingPathComponent("clips").standardizedFileURL.path
        )
    }

    func testEpisodeFolderWithNoClipsSubfolderIsUsedDirectly() throws {
        let folder = try makeEpisode("HT_0379 2026-08-24", withClipsFolder: false)
        let session = try XCTUnwrap(ClipSessionStore.sessions(inRoot: root).first)
        XCTAssertEqual(
            session.clipsFolder.standardizedFileURL.path,
            folder.standardizedFileURL.path,
            "a session made by hand must still work"
        )
    }

    func testEmptyRootHasNoSessions() {
        XCTAssertTrue(ClipSessionStore.sessions(inRoot: root).isEmpty)
    }

    // MARK: - Reading a session back from a path

    func testSessionIsReadBackFromAClipsFolder() {
        let clips = URL(fileURLWithPath: "/Users/sev/Desktop/Hacks on Tap/HT_0379 2026-08-24/clips")
        let session = ClipSessionStore.session(forClipsFolder: clips)
        XCTAssertEqual(session.title, "HT_0379 2026-08-24")
        XCTAssertEqual(session.clipsFolder, clips)
    }

    func testAFolderNotNamedClipsIsTheEpisodeItself() {
        let folder = URL(fileURLWithPath: "/Users/sev/Desktop/Hacks on Tap/HT_0379 2026-08-24")
        let session = ClipSessionStore.session(forClipsFolder: folder)
        XCTAssertEqual(session.title, "HT_0379 2026-08-24")
        XCTAssertEqual(session.clipsFolder, folder)
    }

    func testShowRootIsInferredFromAClipsFolder() {
        let clips = URL(fileURLWithPath: "/Users/sev/Desktop/Hacks on Tap/HT_0379 2026-08-24/clips")
        XCTAssertEqual(
            ClipSessionStore.inferredRoot(forClipsFolder: clips).path,
            "/Users/sev/Desktop/Hacks on Tap"
        )
    }

    // MARK: - Naming the next session

    private let aug24 = Date(timeIntervalSince1970: 1_787_529_600)  // 2026-08-24 UTC

    func testNextTitleIncrementsFromTheHighestEpisode() throws {
        try makeEpisode("HT_0378 2026-08-10")
        try makeEpisode("HT_0379 2026-08-17")
        XCTAssertEqual(
            ClipSessionStore.nextTitle(inRoot: root, date: aug24),
            "HT_0380 \(ClipSessionStore.dateString(aug24))"
        )
    }

    func testNextTitleKeepsTheZeroPaddingAlreadyInUse() throws {
        try makeEpisode("HT_12 2026-08-17")
        XCTAssertEqual(
            ClipSessionStore.nextTitle(inRoot: root, date: aug24),
            "HT_13 \(ClipSessionStore.dateString(aug24))"
        )
    }

    func testNextTitleRollsPastTheDigitWidthWhenItHasTo() throws {
        try makeEpisode("HT_0999 2026-08-17")
        XCTAssertEqual(
            ClipSessionStore.nextTitle(inRoot: root, date: aug24).hasPrefix("HT_1000 "),
            true
        )
    }

    func testFoldersThatAreNotEpisodesAreIgnoredWhenNumbering() throws {
        try makeEpisode("HT_0379 2026-08-17")
        try makeEpisode("Archive")
        try makeEpisode("HTML notes")
        XCTAssertEqual(ClipSessionStore.nextEpisodeNumber(inRoot: root).number, 380)
    }

    func testFirstEpisodeInAnEmptyRoot() {
        XCTAssertEqual(ClipSessionStore.nextEpisodeNumber(inRoot: root).number, 1)
    }

    func testDateStringIsFixedFormat() {
        XCTAssertEqual(ClipSessionStore.dateString(aug24).count, 10)
        XCTAssertEqual(ClipSessionStore.dateString(aug24).filter { $0 == "-" }.count, 2)
    }

    func testEpisodeDigitsOnlyMatchesThePrefix() {
        XCTAssertEqual(ClipSessionStore.episodeDigits("HT_0379 2026-08-24"), "0379")
        XCTAssertNil(ClipSessionStore.episodeDigits("OTW_006 2026-08-24"))
        XCTAssertNil(ClipSessionStore.episodeDigits("HT notes"))
        XCTAssertNil(ClipSessionStore.episodeDigits("Archive"))
    }

    // MARK: - Creating

    func testCreateMakesTheEpisodeAndItsClipsFolder() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.clipsFolder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(session.clipsFolder.lastPathComponent, "clips")
        XCTAssertEqual(session.title, "HT_0380 2026-08-24")
    }

    func testACreatedSessionShowsUpInTheList() throws {
        try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        XCTAssertEqual(ClipSessionStore.sessions(inRoot: root).map(\.title), ["HT_0380 2026-08-24"])
    }
}
