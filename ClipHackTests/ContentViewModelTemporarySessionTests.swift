import XCTest
@testable import ClipHackKit

/// A temporary session files into a folder of its own — the Desktop, in the
/// app — without touching the episode that was open. These pin that: the
/// three saved paths never move, no notes file is written, and nothing about
/// the mode outlives the view model.
@MainActor
final class ContentViewModelTemporarySessionTests: XCTestCase {

    private var root: URL!
    /// Stands in for the Desktop.
    private var desk: URL!

    override func setUpWithError() throws {
        ScratchDefaults.install()
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp-session-tests-\(UUID().uuidString)", isDirectory: true)
        root = scratch.appendingPathComponent("Hacks on Tap", isDirectory: true)
        desk = scratch.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
    }

    override func tearDownWithError() throws {
        ScratchDefaults.uninstall()
    }

    /// A view model with an episode open, the way the app sits on launch.
    private func makeViewModel() throws -> (ContentViewModel, ClipSession) {
        let session = try ClipSessionStore.create(title: "HT_0382 2026-09-22", inRoot: root)
        let vm = ContentViewModel()
        vm.settings.sessionRootPath = root.path
        vm.openSession(session)
        vm.temporarySessionFolder = desk
        return (vm, session)
    }

    /// The three paths that are the episode: show root, downloads, output.
    private func savedPaths(_ settings: ClipHackSettings) -> [String?] {
        [settings.sessionRootPath, settings.downloadDirectoryPath, settings.outputDirectoryPath]
    }

    private func textFiles(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".txt") }
    }

    // MARK: - The saved session is left alone

    func testEnteringAndLeavingLeavesEverySavedFolderAsItWas() throws {
        let (vm, session) = try makeViewModel()
        let before = savedPaths(vm.settings)

        XCTAssertTrue(vm.openTemporarySession())
        XCTAssertEqual(savedPaths(vm.settings), before, "entering writes nothing to settings")
        XCTAssertEqual(savedPaths(ClipHackSettings.load()), before, "nor to what a relaunch reads")

        vm.closeTemporarySession()
        XCTAssertEqual(savedPaths(vm.settings), before)
        XCTAssertEqual(savedPaths(ClipHackSettings.load()), before)
        XCTAssertEqual(vm.currentSession?.title, session.title, "back on the episode that was open")
    }

    func testARelaunchOpensOnTheEpisodeNotTheTemporarySession() throws {
        let (vm, session) = try makeViewModel()
        let before = savedPaths(vm.settings)
        XCTAssertTrue(vm.openTemporarySession())

        let relaunched = ContentViewModel()

        XCTAssertFalse(relaunched.isTemporarySession)
        XCTAssertEqual(relaunched.sessionTitle, session.title)
        XCTAssertEqual(savedPaths(relaunched.settings), before)
    }

    func testOpeningAnEpisodeEndsTheTemporarySession() throws {
        let (vm, session) = try makeViewModel()
        let other = try ClipSessionStore.create(title: "HT_0383 2026-09-29", inRoot: root)
        XCTAssertTrue(vm.openTemporarySession())

        vm.openSession(other)

        XCTAssertFalse(vm.isTemporarySession)
        XCTAssertEqual(vm.sessionTitle, other.title)
        XCTAssertEqual(vm.settings.downloadDirectoryPath, other.clipsFolder.path)
        XCTAssertNotEqual(vm.settings.downloadDirectoryPath, session.clipsFolder.path)
    }

    func testCreatingASessionEndsTheTemporarySession() throws {
        let (vm, _) = try makeViewModel()
        XCTAssertTrue(vm.openTemporarySession())

        XCTAssertTrue(vm.createSession(title: "HT_0383 2026-09-29"))

        XCTAssertFalse(vm.isTemporarySession)
        XCTAssertEqual(vm.sessionTitle, "HT_0383 2026-09-29")
    }

    /// Opening the Desktop as an episode would have adopted the folder above
    /// it — the home folder — as the show. A temporary session never does.
    func testTheShowFolderIsNotAdopted() throws {
        let vm = ContentViewModel()
        vm.temporarySessionFolder = desk
        XCTAssertNil(vm.settings.sessionRootPath)

        XCTAssertTrue(vm.openTemporarySession())

        XCTAssertNil(vm.settings.sessionRootPath)
        XCTAssertNil(vm.settings.downloadDirectoryPath)
        XCTAssertNil(vm.settings.outputDirectoryPath)
    }

    // MARK: - Where things go

    func testDownloadsAndOutputGoToTheTemporaryFolder() throws {
        let (vm, session) = try makeViewModel()
        XCTAssertTrue(vm.openTemporarySession())

        XCTAssertEqual(vm.downloadDirectory, desk)
        XCTAssertEqual(vm.downloadDirectoryDisplayName, "Desktop")
        XCTAssertEqual(vm.processingSettings.outputDirectoryPath, desk.path)
        XCTAssertEqual(vm.settings.outputDirectoryPath, session.clipsFolder.path,
                       "the swap is on the copy a run gets, not the saved settings")

        let input = session.clipsFolder.appendingPathComponent("Some Clip.m4a")
        XCTAssertEqual(
            OutputDirectory.clipHackOutputDirectory(for: input, settings: vm.processingSettings).path,
            desk.path,
            "a clip from the episode's folder is still written to the temporary one"
        )
    }

    func testLeavingSendsOutputBackToTheEpisode() throws {
        let (vm, session) = try makeViewModel()
        XCTAssertTrue(vm.openTemporarySession())
        vm.closeTemporarySession()

        XCTAssertEqual(vm.downloadDirectory.path, session.clipsFolder.path)
        XCTAssertEqual(vm.processingSettings.outputDirectoryPath, session.clipsFolder.path)
    }

    func testTheWindowNamesTheTemporarySession() throws {
        let (vm, session) = try makeViewModel()
        XCTAssertTrue(vm.openTemporarySession())

        XCTAssertEqual(vm.sessionTitle, "Temporary Session")
        XCTAssertEqual(vm.sessionSubtitle, "Desktop")
        XCTAssertNil(vm.currentSession, "no episode is checked in the menu")

        vm.closeTemporarySession()
        XCTAssertEqual(vm.sessionTitle, session.title)
        XCTAssertEqual(vm.sessionSubtitle, root.lastPathComponent)
    }

    // MARK: - No notes file

    func testADownloadWritesNoNotesFile() throws {
        let (vm, session) = try makeViewModel()
        XCTAssertTrue(vm.openTemporarySession())
        let audio = desk.appendingPathComponent("Some Title.m4a")
        try Data("audio".utf8).write(to: audio)

        vm.clipNotesEnabled = true
        vm.downloadPersonField = "Trump"
        vm.downloadNotesField = "the good part"
        vm.downloadTimestampField = "1:13 to :55"
        vm.finishDownload(sourceURL: "https://x.com/a/status/1", filePath: audio.path)

        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(vm.files[0].notes, "Trump — the good part", "notes still ride on the row")
        XCTAssertEqual(try textFiles(in: desk), [], "no notes file beside the download")
        XCTAssertEqual(try textFiles(in: session.clipsFolder), [], "and none in the episode")
        XCTAssertTrue(vm.clipNotesEnabled, "the episodes' preference is kept, not cleared")
    }

    /// A download started in a temporary session and finished after leaving it
    /// must not land a block in the episode's notes — its audio is elsewhere.
    func testADownloadStartedInTheTemporarySessionRecordsNothingAfterLeaving() throws {
        let (vm, session) = try makeViewModel()
        vm.clipNotesEnabled = true
        XCTAssertTrue(vm.openTemporarySession())
        let notesFile = vm.downloadNotesFile
        XCTAssertNil(notesFile)
        let audio = desk.appendingPathComponent("Some Title.m4a")
        try Data("audio".utf8).write(to: audio)

        vm.closeTemporarySession()
        vm.finishDownload(sourceURL: "https://x.com/a/status/1", filePath: audio.path, notesFile: notesFile)

        XCTAssertEqual(try textFiles(in: session.clipsFolder), [])
    }

    /// The already-downloaded check folds any notes files it finds into the
    /// session's one. On a Desktop that would make a `Desktop.txt`.
    func testTheAlreadyDownloadedCheckDoesNotGatherNotesFiles() throws {
        let (vm, _) = try makeViewModel()
        let audio = desk.appendingPathComponent("Some Title.m4a")
        try Data("audio".utf8).write(to: audio)
        try ClipNotesFile.write(notes: "n", sourceURL: "https://a", forAudioFile: audio)
        let before = try textFiles(in: desk)
        XCTAssertTrue(vm.openTemporarySession())

        XCTAssertFalse(vm.adoptAlreadyDownloadedClip(for: "https://a", in: desk))

        XCTAssertEqual(try textFiles(in: desk), before)
        XCTAssertTrue(vm.files.isEmpty)
    }

    // MARK: - An unwritable folder

    func testAFolderThatCannotBeWrittenRefusesTheTemporarySession() throws {
        let (vm, _) = try makeViewModel()
        // A file where the folder should be: it can be neither made nor written.
        let blocked = desk.appendingPathComponent("Blocked")
        try Data().write(to: blocked)
        vm.temporarySessionFolder = blocked

        XCTAssertFalse(vm.openTemporarySession())

        XCTAssertFalse(vm.isTemporarySession)
        XCTAssertEqual(vm.alertTitle, "Temporary Session Unavailable")
        XCTAssertTrue(vm.alertMessage?.contains("Files and Folders") ?? false)
    }

    /// The writable-output check in `process()` looks at the folder the run
    /// will actually use, not the saved one.
    func testProcessingStopsWhenTheTemporaryFolderStopsBeingWritable() throws {
        let (vm, session) = try makeViewModel()
        let clip = session.clipsFolder.appendingPathComponent("clip.wav")
        try Data("audio".utf8).write(to: clip)
        vm.files = [FileItem(url: clip)]
        vm.files[0].status = .ready(AudioStats(rms: -20, peak: -3, crest: 17, lufs: -19))
        XCTAssertTrue(vm.openTemporarySession())

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: desk.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: desk.path) }
        vm.process()

        XCTAssertFalse(vm.isProcessing)
        XCTAssertEqual(vm.alertTitle, "Error")
        XCTAssertTrue(vm.alertMessage?.contains("Files and Folders") ?? false,
                      "the saved folder is writable; the temporary one is what was checked")
    }
}
