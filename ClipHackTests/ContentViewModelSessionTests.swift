import XCTest
@testable import ClipHackKit

@MainActor
final class ContentViewModelSessionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try ScratchDefaults.install()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-vm-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        ScratchDefaults.uninstall()
    }

    private func makeViewModel() -> ContentViewModel {
        let vm = ContentViewModel()
        vm.settings.sessionRootPath = root.path
        return vm
    }

    // MARK: - Opening

    func testOpeningASessionPointsBothFoldersAtIt() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-24", in: root)
        let vm = makeViewModel()

        vm.openSession(session)

        XCTAssertEqual(vm.settings.downloadDirectoryPath, session.clipsFolder.path)
        XCTAssertEqual(vm.settings.outputDirectoryPath, session.clipsFolder.path,
                       "an episode's sources and its finished audio belong together")
    }

    func testSessionTitleFollowsTheOpenSession() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-24", in: root)
        let vm = makeViewModel()
        XCTAssertEqual(vm.sessionTitle, "ClipHack", "no session yet")

        vm.openSession(session)
        XCTAssertEqual(vm.sessionTitle, "HT_0380 2026-08-24")
        XCTAssertEqual(vm.currentSession?.folder.lastPathComponent, "HT_0380 2026-08-24")
    }

    /// Listings of the temporary folder can spell it /private/var;
    /// standardizing drops that, as the store's own tests do.
    private func standardized(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    /// An episode folder can be read before its clips folder is made in it.
    /// The next look moves into the clips folder.
    func testAClipsFolderMadeAfterTheEpisodeIsMovedInto() throws {
        let episode = root.appendingPathComponent("HT_0383 2026-09-29", isDirectory: true)
        try FileManager.default.createDirectory(at: episode, withIntermediateDirectories: true)
        let vm = makeViewModel()
        vm.followNewestEpisode()
        XCTAssertEqual(standardized(vm.settings.downloadDirectoryPath), episode.standardizedFileURL.path,
                       "an episode with no clips folder is used as it is")
        XCTAssertFalse(FileManager.default.fileExists(atPath: episode.appendingPathComponent("clips").path),
                       "ClipHack never makes the clips folder")

        let clips = episode.appendingPathComponent("clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        vm.followNewestEpisode()

        XCTAssertEqual(standardized(vm.settings.downloadDirectoryPath), clips.standardizedFileURL.path)
        XCTAssertEqual(standardized(vm.settings.outputDirectoryPath), clips.standardizedFileURL.path)
    }

    // MARK: - Naming the folders

    func testBothFolderRowsNameTheSessionsClipsFolder() throws {
        let session = try makePreppedEpisode("HT_0382 2026-09-22", in: root)
        let vm = makeViewModel()
        vm.openSession(session)

        XCTAssertEqual(vm.downloadDirectoryDisplayName, "HT_0382 2026-09-22/clips")
        XCTAssertEqual(ContentViewModel.folderDisplayName(try XCTUnwrap(vm.settings.outputDirectoryPath)),
                       "HT_0382 2026-09-22/clips",
                       "OUTPUT DIR read just \"clips\", the same for every session")
    }

    func testAFolderOutsideASessionIsNamedByItself() {
        XCTAssertEqual(ContentViewModel.folderDisplayName("/Users/example/Music/Renders"), "Renders")
        XCTAssertEqual(ContentViewModel.folderDisplayName("/Users/example/Show/HT_0381 2026-09-15"),
                       "HT_0381 2026-09-15")
    }

    // MARK: - Following the newest episode

    func testTheNewestEpisodeIsFollowed() throws {
        try makePreppedEpisode("HT_0378 2026-08-10", in: root)
        let newest = try makePreppedEpisode("HT_0380 2026-08-24", in: root)
        try makePreppedEpisode("HT_0379 2026-08-17", in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("TEMPLATES"), withIntermediateDirectories: true)
        let vm = makeViewModel()

        vm.followNewestEpisode()

        XCTAssertEqual(vm.sessionTitle, "HT_0380 2026-08-24")
        XCTAssertEqual(standardized(vm.settings.downloadDirectoryPath), standardized(newest.clipsFolder.path))
        XCTAssertEqual(standardized(vm.settings.outputDirectoryPath), standardized(newest.clipsFolder.path))
    }

    /// The weekly shape: prep makes the next episode and clears the last
    /// one's clips folder out, while ClipHack still points at it.
    func testPrepsNextEpisodeIsMovedTo() throws {
        let last = try makePreppedEpisode("HT_0385 2026-10-13", in: root)
        let vm = makeViewModel()
        vm.openSession(last)

        let next = try makePreppedEpisode("HT_0386 2026-10-20", in: root)
        try FileManager.default.removeItem(at: last.clipsFolder)
        vm.followNewestEpisode()

        XCTAssertEqual(vm.sessionTitle, "HT_0386 2026-10-20")
        XCTAssertEqual(standardized(vm.settings.downloadDirectoryPath), standardized(next.clipsFolder.path))
    }

    func testFoldersThatAreNotEpisodesAreNeverFollowed() throws {
        for name in ["TEMPLATES", "Ads", "Audio assets"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let vm = makeViewModel()
        vm.followNewestEpisode()
        XCTAssertNil(vm.settings.downloadDirectoryPath)
        XCTAssertEqual(vm.sessionTitle, "ClipHack")
    }

    func testTheShowFolderIsTakenFromTheOpenEpisodeWhenNoneIsSet() throws {
        let open = try makePreppedEpisode("HT_0380 2026-08-24", in: root)
        let newest = try makePreppedEpisode("HT_0381 2026-08-31", in: root)
        let vm = ContentViewModel()
        vm.settings.sessionRootPath = nil
        vm.settings.downloadDirectoryPath = open.clipsFolder.path

        vm.followNewestEpisode()

        XCTAssertEqual(vm.settings.sessionRootPath, root.standardizedFileURL.path)
        XCTAssertEqual(standardized(vm.settings.downloadDirectoryPath), newest.clipsFolder.standardizedFileURL.path)
    }

    // MARK: - Presets must not move folders

    func testApplyingAPresetKeepsEveryFolderTheUserChose() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-24", in: root)
        let vm = makeViewModel()
        vm.openSession(session)

        let preset = try XCTUnwrap(ClipHackPreset.builtIn.first)
        vm.applyPreset(preset)

        XCTAssertEqual(vm.settings.downloadDirectoryPath, session.clipsFolder.path,
                       "a preset changes processing, not where files live")
        XCTAssertEqual(vm.settings.outputDirectoryPath, session.clipsFolder.path)
        XCTAssertEqual(vm.settings.sessionRootPath, root.path)
        XCTAssertEqual(vm.sessionTitle, "HT_0380 2026-08-24",
                       "switching preset must not drop you out of your session")
    }
    func testSubtitleNamesTheShowAndIsEmptyWithoutASession() throws {
        let vm = makeViewModel()
        XCTAssertEqual(vm.sessionSubtitle, "", "no session, no subtitle")

        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        vm.openSession(session)
        XCTAssertEqual(vm.sessionSubtitle, root.lastPathComponent)
    }
    func testChoosingAnEpisodeAsTheShowFolderResolvesUpward() throws {
        let session = try makePreppedEpisode("HT_0379 2026-08-24", in: root)
        let vm = makeViewModel()
        vm.sessionRootPicker = { session.folder.path }

        XCTAssertTrue(vm.chooseSessionRoot())
        XCTAssertEqual(vm.settings.sessionRootPath, root.path)
        XCTAssertEqual(vm.sessionTitle, "HT_0379 2026-08-24", "and its newest episode is opened")
    }
    // MARK: - Editing the clip list targets the right clip

    // MARK: - One file per session

    func testDownloadsLandInTheSessionFile() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let audio = session.clipsFolder.appendingPathComponent("Some Title 1.13 to .55.m4a")
        try Data("audio".utf8).write(to: audio)

        let vm = makeViewModel()
        vm.openSession(session)
        vm.downloadTimestampField = "1:13 to :55"
        vm.finishDownload(sourceURL: "https://x.com/a/status/1", filePath: audio.path)

        let file = SessionNotesFile.url(inClipsFolder: session.clipsFolder, title: session.title)
        let records = SessionNotesFile.read(at: file)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.filename, "Some Title 1.13 to .55.m4a")
        XCTAssertEqual(records.first?.timestamp, "1:13 to :55")
        XCTAssertEqual(records.first?.sourceURL, "https://x.com/a/status/1")
    }

    /// A download is recorded in the notes of the session it was started in,
    /// which is where its audio went — not whichever is open when it ends.
    func testADownloadFinishedAfterSwitchingIsRecordedWhereItStarted() throws {
        let started = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let switched = try makePreppedEpisode("HT_0381 2026-09-07", in: root)
        let audio = started.clipsFolder.appendingPathComponent("Some Title.m4a")
        try Data("audio".utf8).write(to: audio)

        let vm = makeViewModel()
        vm.openSession(started)
        let notesFile = vm.downloadNotesFile
        vm.openSession(switched)
        vm.finishDownload(sourceURL: "https://a", filePath: audio.path, notesFile: notesFile)

        let startedFile = SessionNotesFile.url(inClipsFolder: started.clipsFolder, title: started.title)
        let switchedFile = SessionNotesFile.url(inClipsFolder: switched.clipsFolder, title: switched.title)
        XCTAssertEqual(SessionNotesFile.read(at: startedFile).map(\.filename), ["Some Title.m4a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: switchedFile.path))
    }

    func testAClipAlreadyInTheSessionIsAdoptedRatherThanRefetched() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let audio = session.clipsFolder.appendingPathComponent("Some Title.m4a")
        try Data("audio".utf8).write(to: audio)

        let file = SessionNotesFile.url(inClipsFolder: session.clipsFolder, title: session.title)
        try SessionNotesFile.write([
            ClipRecord(filename: "Some Title.m4a", sourceURL: "https://x.com/a/status/1"),
        ], to: file)

        let vm = makeViewModel()
        vm.openSession(session)
        XCTAssertTrue(vm.adoptAlreadyDownloadedClip(for: "https://x.com/a/status/1?s=43", in: session.clipsFolder),
                      "the same post with tracking params is the same clip")
        XCTAssertEqual(vm.files.count, 1)
    }

    /// Its file has moved on — processed with the original trashed, or filed
    /// by the clip skill — but its block is still there. ClipHack asks before
    /// fetching it again, rather than handing the skill a duplicate.
    func testALinkWhoseFileHasMovedOnIsAskedAboutBeforeDownloading() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let file = SessionNotesFile.url(inClipsFolder: session.clipsFolder, title: session.title)
        try SessionNotesFile.write([
            ClipRecord(filename: "Gone.m4a", sourceURL: "https://x.com/a/status/1"),
        ], to: file)
        let vm = makeViewModel()
        vm.openSession(session)
        XCTAssertFalse(vm.adoptAlreadyDownloadedClip(for: "https://x.com/a/status/1", in: session.clipsFolder),
                       "nothing on disk to add instead")

        vm.downloadURLField = "https://x.com/a/status/1?s=43"
        vm.startDownload()

        XCTAssertEqual(vm.downloadState, .alreadyDownloaded(url: "https://x.com/a/status/1?s=43", filename: "Gone.m4a"))
        XCTAssertFalse(vm.isDownloading)
        XCTAssertEqual(vm.downloadURLField, "https://x.com/a/status/1?s=43", "the form is kept for Download Again")
    }

    /// Download Again only answers the question that was asked.
    func testDownloadAgainWithoutBeingAskedStillAsks() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let file = SessionNotesFile.url(inClipsFolder: session.clipsFolder, title: session.title)
        try SessionNotesFile.write([
            ClipRecord(filename: "Gone.m4a", sourceURL: "https://a"),
        ], to: file)
        let vm = makeViewModel()
        vm.openSession(session)
        vm.downloadURLField = "https://a"

        vm.startDownload(again: true)

        XCTAssertEqual(vm.downloadState, .alreadyDownloaded(url: "https://a", filename: "Gone.m4a"))
        XCTAssertFalse(vm.isDownloading)
    }

    func testTypingAnotherLinkTakesTheQuestionAway() throws {
        let session = try makePreppedEpisode("HT_0380 2026-08-31", in: root)
        let file = SessionNotesFile.url(inClipsFolder: session.clipsFolder, title: session.title)
        try SessionNotesFile.write([ClipRecord(filename: "Gone.m4a", sourceURL: "https://a")], to: file)
        let vm = makeViewModel()
        vm.openSession(session)
        vm.downloadURLField = "https://a"
        vm.startDownload()

        vm.downloadURLField = "https://b"
        vm.downloadURLFieldChanged()

        XCTAssertEqual(vm.downloadState, .idle)
    }
}
