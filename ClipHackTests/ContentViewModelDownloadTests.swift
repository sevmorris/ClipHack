import XCTest
@testable import ClipHackKit

@MainActor
final class ContentViewModelDownloadTests: XCTestCase {

    // These tests construct real view models and assign settings, which persist
    // on every change — without this they rewrite the user's actual folders.
    override func setUpWithError() throws {
        try super.setUpWithError()
        try ScratchDefaults.install()
    }

    override func tearDown() {
        ScratchDefaults.uninstall()
        super.tearDown()
    }

    private func makeViewModel() -> ContentViewModel {
        ContentViewModel()
    }

    // MARK: - URL validation

    func testValidatedWebURLAcceptsHTTPAndHTTPSWithWhitespace() {
        XCTAssertEqual(
            ContentViewModel.validatedWebURL("  https://youtu.be/abc123 \n"),
            "https://youtu.be/abc123"
        )
        XCTAssertEqual(
            ContentViewModel.validatedWebURL("http://example.com/audio"),
            "http://example.com/audio"
        )
    }

    func testValidatedWebURLRejectsNonWebInput() {
        XCTAssertNil(ContentViewModel.validatedWebURL("file:///Users/test/song.wav"))
        XCTAssertNil(ContentViewModel.validatedWebURL("ftp://example.com/file"))
        XCTAssertNil(ContentViewModel.validatedWebURL("not a url"))
        XCTAssertNil(ContentViewModel.validatedWebURL(""))
        XCTAssertNil(ContentViewModel.validatedWebURL("   "))
    }

    // MARK: - Dropped URLs prefill only (never auto-download)

    func testDroppedURLPrefillsFieldAndOpensPopoverWithoutDownloading() {
        let vm = makeViewModel()
        let accepted = vm.acceptDroppedURL("https://example.com/watch?v=abc")

        XCTAssertTrue(accepted)
        XCTAssertEqual(vm.downloadURLField, "https://example.com/watch?v=abc")
        XCTAssertTrue(vm.isDownloadPopoverPresented)
        XCTAssertEqual(vm.downloadState, .idle, "a drop must never start the download by itself")
    }

    func testDroppedURLClearsStaleFailure() {
        let vm = makeViewModel()
        vm.downloadState = .failed("previous error")
        vm.acceptDroppedURL("https://example.com/next")
        XCTAssertEqual(vm.downloadState, .idle)
    }

    func testDroppedURLReplacesExistingFieldContent() {
        let vm = makeViewModel()
        vm.downloadURLField = "https://example.com/old"
        vm.acceptDroppedURL("https://example.com/new")
        XCTAssertEqual(vm.downloadURLField, "https://example.com/new")
    }

    func testDroppedFileURLIsRejectedAndChangesNothing() {
        let vm = makeViewModel()
        let accepted = vm.acceptDroppedURL("file:///Users/test/song.wav")

        XCTAssertFalse(accepted)
        XCTAssertEqual(vm.downloadURLField, "")
        XCTAssertFalse(vm.isDownloadPopoverPresented)
    }

    // MARK: - Start guard

    func testStartDownloadWithInvalidFieldFailsWithoutRunning() {
        let vm = makeViewModel()
        vm.downloadURLField = "not a url"
        vm.startDownload()

        XCTAssertEqual(vm.downloadState, .failed("Enter a valid http(s) URL."))
        XCTAssertFalse(vm.isDownloading)
    }

    // MARK: - Completion feeds the existing add-files path

    func testFinishDownloadAddsRowSelectsItAndClearsPopoverState() {
        let vm = makeViewModel()
        vm.downloadURLField = "https://example.com/watch?v=abc"
        vm.isDownloadPopoverPresented = true

        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Some_Title.m4a"
        )

        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(vm.files[0].url.lastPathComponent, "Some_Title.m4a")
        XCTAssertEqual(vm.selectedFileIDs, [vm.files[0].id])
        XCTAssertEqual(vm.downloadURLField, "")
        XCTAssertFalse(vm.isDownloadPopoverPresented)
    }

    func testFinishDownloadClearsNameField() {
        let vm = makeViewModel()
        vm.downloadNameField = "My Clip"
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/My_Clip.m4a"
        )
        XCTAssertEqual(vm.downloadNameField, "")
    }

    // MARK: - The clip notes file

    /// A stand-in for the clip folder a download now lands in.
    private func makeClipFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-vm-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testClipNotesWrittenIntoTheClipFolderWhenEnabled() throws {
        let dir = try makeClipFolder()

        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )

        let content = try String(contentsOf: vm.sessionNotesURL, encoding: .utf8)
        XCTAssertEqual(content, "Title.m4a\n    https://example.com/watch?v=abc\n")
    }

    func testAHandTypedNameIsStillRecorded() throws {
        let dir = try makeClipFolder()
        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        vm.downloadNameField = "Title"          // named by hand
        vm.downloadTimestampField = "1:13 to :55"
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )

        XCTAssertEqual(
            try String(contentsOf: vm.sessionNotesURL, encoding: .utf8),
            "Title.m4a\n    CUT  1:13 to :55\n    https://example.com/watch?v=abc\n",
            "the name is the only thing saying which clip a block is"
        )
    }

    func testTheCutGoesOnItsOwnLine() throws {
        let dir = try makeClipFolder()
        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        vm.downloadTimestampField = "1:13 to :55"
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )

        XCTAssertEqual(
            try String(contentsOf: vm.sessionNotesURL, encoding: .utf8),
            "Title.m4a\n    CUT  1:13 to :55\n    https://example.com/watch?v=abc\n"
        )
        let record = try XCTUnwrap(SessionNotesFile.read(at: vm.sessionNotesURL).first)
        XCTAssertEqual(record.timestamp, "1:13 to :55", "the cut is kept on its own line")
        XCTAssertEqual(record.sourceURL, "https://example.com/watch?v=abc")
    }

    /// The next download rewrites the file, and keeps every earlier clip's
    /// name, cut and link as they were.
    func testEarlierClipsSurviveTheNextDownload() throws {
        let dir = try makeClipFolder()
        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        let earlier = "Old 0.30 to .12.m4a\n    CUT  :30 to :12\n    https://example.com/old\n"
        try Data(earlier.utf8).write(to: vm.sessionNotesURL)

        vm.finishDownload(
            sourceURL: "https://example.com/new",
            filePath: dir.appendingPathComponent("New.m4a").path
        )

        XCTAssertEqual(
            try String(contentsOf: vm.sessionNotesURL, encoding: .utf8),
            earlier + "\nNew.m4a\n    https://example.com/new\n"
        )
    }

    // MARK: - Clips added from disk, and cuts

    /// A view model whose session is a fresh clip folder.
    private func makeSessionViewModel() throws -> (ContentViewModel, URL) {
        let dir = try makeClipFolder()
        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        return (vm, dir)
    }

    /// The notes file records downloads, and cuts; a file added from disk
    /// with neither has nothing in it.
    func testAFileAddedFromDiskIsNotListed() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([dir.appendingPathComponent("Talarico for TX Senate.wav")])

        XCTAssertEqual(vm.files.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vm.sessionNotesURL.path))
    }

    func testAClipHackOutputAddedAgainIsNotListed() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([dir.appendingPathComponent("Texas PAC-44knorm-clipped-1dB.wav")])
        vm.confirmReprocessWarning()

        XCTAssertEqual(vm.files.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vm.sessionNotesURL.path))
    }

    func testADownloadIsListedOnceWithItsLink() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )
        XCTAssertEqual(SessionNotesFile.read(at: vm.sessionNotesURL).map(\.sourceURL),
                       ["https://example.com/watch?v=abc"], "not also listed by name")
    }

    /// An audio file in `dir` for a cut to rename. A row is renamable only
    /// once its analysis has finished, which in a test never comes, so the
    /// row is marked as having got that far.
    private func makeAudio(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("audio".utf8).write(to: url)
        return url
    }

    private func settle(_ vm: ContentViewModel) {
        for index in vm.files.indices { vm.files[index].status = .pending }
    }

    private func names(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasSuffix(".txt") }
            .sorted()
    }

    func testSettingACutRenamesTheFileWritesItUnderTheClipAndShowsItOnTheRow() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([try makeAudio("Collins.wav", in: dir)])
        settle(vm)
        let id = try XCTUnwrap(vm.files.first?.id)

        vm.beginCut(id)
        vm.cutField = " :18 to end "
        vm.confirmCut()

        XCTAssertEqual(vm.files.first?.cut, ":18 to end")
        XCTAssertEqual(vm.files.first?.url.lastPathComponent, "Collins .18 to end.wav")
        XCTAssertEqual(try names(in: dir), ["Collins .18 to end.wav"])
        XCTAssertEqual(
            try String(contentsOf: vm.sessionNotesURL, encoding: .utf8),
            "Collins .18 to end.wav\n    CUT  :18 to end\n",
            "the block follows the file to its new name"
        )

        vm.setCut("", for: id)
        XCTAssertNil(vm.files.first?.cut)
        XCTAssertEqual(try names(in: dir), ["Collins.wav"], "removing the cut takes it out of the name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vm.sessionNotesURL.path),
                       "with its cut gone, a clip added from disk has nothing left to record")
    }

    func testChangingADownloadsCutReplacesItInTheNameAndKeepsItsLink() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.downloadTimestampField = "1:13 to :55"
        // yt-dlp has already named it with the cut by the time it finishes.
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: try makeAudio("Title 1.13 to .55.m4a", in: dir).path
        )
        settle(vm)
        let id = try XCTUnwrap(vm.files.first?.id)
        XCTAssertEqual(vm.files.first?.cut, "1:13 to :55", "the download's cut shows on its row")

        vm.setCut("0:20 to end", for: id)
        XCTAssertEqual(try names(in: dir), ["Title 0.20 to end.m4a"], "the old cut is replaced, not added to")
        let records = SessionNotesFile.read(at: vm.sessionNotesURL)
        XCTAssertEqual(records.map(\.filename), ["Title 0.20 to end.m4a"])
        XCTAssertEqual(records.map(\.timestamp), ["0:20 to end"])
        XCTAssertEqual(records.map(\.sourceURL), ["https://example.com/watch?v=abc"])
    }

    func testACutGoesOnTheEndOfANameThatDoesNotHaveTheRowsCut() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([try makeAudio("Hamilton.wav", in: dir)])
        settle(vm)
        let id = try XCTUnwrap(vm.files.first?.id)
        // A cut set before cuts went into names: the row has it, the name doesn't.
        vm.files[0].cut = "1:23 to :52"

        vm.setCut("1:30 to :52", for: id)
        XCTAssertEqual(try names(in: dir), ["Hamilton 1.30 to .52.wav"])
    }

    func testACutWhoseNameIsTakenChangesNothing() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([try makeAudio("Collins.wav", in: dir)])
        _ = try makeAudio("Collins 1.13 to .55.wav", in: dir)
        settle(vm)
        let id = try XCTUnwrap(vm.files.first?.id)

        vm.setCut("1:13 to :55", for: id)
        XCTAssertNil(vm.files.first?.cut)
        XCTAssertEqual(vm.files.first?.url.lastPathComponent, "Collins.wav")
        XCTAssertEqual(vm.alertTitle, "Cut Not Set")
        XCTAssertTrue(SessionNotesFile.read(at: vm.sessionNotesURL).isEmpty,
                      "the notes don't record a cut the name couldn't take")
    }

    /// Renaming under a running ffprobe would pull the file out from under it.
    func testACutCannotBeSetWhileTheClipIsAnalyzed() throws {
        let (vm, dir) = try makeSessionViewModel()
        vm.addFiles([try makeAudio("Collins.wav", in: dir)])
        let file = try XCTUnwrap(vm.files.first)
        XCTAssertEqual(file.status, .analyzing)
        XCTAssertFalse(vm.canSetCut(file))

        vm.beginCut(file.id)
        XCTAssertNil(vm.cutTargetID)
        vm.setCut("1:13 to :55", for: file.id)
        XCTAssertEqual(try names(in: dir), ["Collins.wav"])
        XCTAssertNil(vm.files.first?.cut)
    }

    func testARestoredClipArrivesWithItsCut() throws {
        let (vm, dir) = try makeSessionViewModel()
        try SessionNotesFile.setCut("1:23 to :52", filename: "Hamilton.wav", at: vm.sessionNotesURL)
        vm.addFiles([dir.appendingPathComponent("Hamilton.wav")])
        XCTAssertEqual(vm.files.first?.cut, "1:23 to :52")
    }

    /// Before, a clip named by hand recorded no filename, so its block could
    /// not be traced back to the audio and the link was fetched again.
    func testAHandNamedClipIsRecognisedWhenItsLinkIsUsedAgain() throws {
        let dir = try makeClipFolder()
        let audio = dir.appendingPathComponent("Title.m4a")
        try Data("audio".utf8).write(to: audio)

        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        vm.downloadNameField = "Title"          // named by hand
        vm.finishDownload(sourceURL: "https://example.com/watch?v=abc", filePath: audio.path)

        // Days later, in a fresh window.
        let later = makeViewModel()
        XCTAssertTrue(later.adoptAlreadyDownloadedClip(for: "https://example.com/watch?v=abc", in: dir))
        XCTAssertEqual(later.files.count, 1)
    }

    func testDuplicateURLWritesNoClipNotes() throws {
        let dir = try makeClipFolder()

        let vm = makeViewModel()
        vm.settings.downloadDirectoryPath = dir.path
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )
        let notesURL = vm.sessionNotesURL
        let afterFirst = try String(contentsOf: notesURL, encoding: .utf8)

        vm.downloadURLField = "https://example.com/watch?v=abc"
        vm.downloadTimestampField = "should not be logged"
        vm.startDownload()

        XCTAssertEqual(try String(contentsOf: notesURL, encoding: .utf8), afterFirst,
                       "a duplicate-URL selection downloads nothing and logs nothing")
        XCTAssertEqual(vm.downloadTimestampField, "", "the duplicate path clears the form")
    }

    // MARK: - Folder drops

    func testDroppingAFolderAddsTheAudioInside() throws {
        let root = try makeClipFolder()
        for stem in ["B Clip", "A Clip"] {
            let folder = root.appendingPathComponent(stem, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("audio".utf8).write(to: folder.appendingPathComponent("\(stem).m4a"))
        }

        // Dropping a whole show's worth of clip folders finds them all.
        let vm = makeViewModel()
        vm.addFiles([root])

        XCTAssertEqual(vm.files.map { $0.url.lastPathComponent }, ["A Clip.m4a", "B Clip.m4a"],
                       "folder contents arrive in name order")
        XCTAssertNil(vm.alertMessage, "a folder of audio is not a notice")
    }

    /// The uncut copies in `orig` are of clips already in the folder above;
    /// dropping the clips folder must not add them a second time.
    func testDroppingAFolderPassesOverItsOrigCopies() throws {
        let root = try makeClipFolder()
        try Data("audio".utf8).write(to: root.appendingPathComponent("Clip.wav"))
        let orig = root.appendingPathComponent("orig", isDirectory: true)
        try FileManager.default.createDirectory(at: orig, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: orig.appendingPathComponent("Clip.wav"))

        let vm = makeViewModel()
        vm.addFiles([root])

        XCTAssertEqual(vm.files.map { $0.url.deletingLastPathComponent().lastPathComponent },
                       [root.lastPathComponent])
    }

    /// Redoing a cut starts from the copy, so the orig folder itself can be dropped.
    func testDroppingTheOrigFolderItselfAddsItsCopies() throws {
        let root = try makeClipFolder()
        let orig = root.appendingPathComponent("orig", isDirectory: true)
        try FileManager.default.createDirectory(at: orig, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: orig.appendingPathComponent("Clip.wav"))

        let vm = makeViewModel()
        vm.addFiles([orig])

        XCTAssertEqual(vm.files.map(\.url.lastPathComponent), ["Clip.wav"])
    }

    func testDroppingAFolderTwiceDoesNotDoubleTheRows() throws {
        let root = try makeClipFolder()
        try Data("audio".utf8).write(to: root.appendingPathComponent("One.m4a"))

        let vm = makeViewModel()
        vm.addFiles([root])
        vm.addFiles([root])

        XCTAssertEqual(vm.files.count, 1)
    }

    func testDroppingAFolderWithNoAudioReportsIt() throws {
        let root = try makeClipFolder()
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let vm = makeViewModel()
        vm.addFiles([empty])

        XCTAssertTrue(vm.files.isEmpty)
        XCTAssertEqual(vm.alertMessage, "1 folder skipped — no audio inside.")
    }

    // MARK: - Cross-session duplicate downloads

    /// The session's notes file records `filename` as downloaded from `link`.
    private func recordDownload(_ filename: String, from link: String, in dir: URL, vm: ContentViewModel) throws {
        try SessionNotesFile.upsert(
            ClipRecord(filename: filename, sourceURL: link),
            at: vm.sessionNotesURL(for: dir)
        )
    }

    func testDownloadingALinkAlreadyOnDiskAdoptsTheExistingClip() throws {
        let dir = try makeClipFolder()
        let audio = dir.appendingPathComponent("Title.m4a")
        try Data("audio".utf8).write(to: audio)

        let vm = makeViewModel()
        try recordDownload("Title.m4a", from: "https://a/clip", in: dir, vm: vm)
        XCTAssertTrue(vm.adoptAlreadyDownloadedClip(for: "https://a/clip", in: dir))

        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(
            vm.files[0].url.resolvingSymlinksInPath().path,
            audio.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(vm.selectedFileIDs, [vm.files[0].id])
        XCTAssertEqual(vm.alertTitle, "Already Downloaded")
        XCTAssertFalse(vm.isDownloadPopoverPresented)
        XCTAssertEqual(vm.existingDownloadRowID(for: "https://a/clip"), vm.files[0].id,
                       "adopting should also seed the session dedupe")
    }

    func testAdoptingSelectsARowThatIsAlreadyListedInsteadOfAddingIt() throws {
        let dir = try makeClipFolder()
        let audio = dir.appendingPathComponent("Title.m4a")
        try Data("audio".utf8).write(to: audio)

        let vm = makeViewModel()
        try recordDownload("Title.m4a", from: "https://a/clip", in: dir, vm: vm)
        vm.addFiles([audio])
        XCTAssertTrue(vm.adoptAlreadyDownloadedClip(for: "https://a/clip", in: dir))
        XCTAssertEqual(vm.files.count, 1, "the clip was already in the list")
    }

    func testAnUnseenLinkIsNotAdopted() throws {
        let dir = try makeClipFolder()
        let vm = makeViewModel()
        XCTAssertFalse(vm.adoptAlreadyDownloadedClip(for: "https://a/never-seen", in: dir))
        XCTAssertTrue(vm.files.isEmpty)
    }

    // MARK: - Re-using a link

    func testDuplicateURLClearsNameFieldWithoutDownloading() {
        let vm = makeViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )
        vm.downloadURLField = "https://example.com/watch?v=abc"
        vm.downloadNameField = "Different Name"
        vm.startDownload()

        XCTAssertEqual(vm.downloadState, .idle,
                       "same URL with a new name still selects the existing row")
        XCTAssertEqual(vm.downloadNameField, "")
    }

    func testFinishDownloadWithUnsupportedExtensionAddsNothing() {
        let vm = makeViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/exotic",
            filePath: "/tmp/cliphack-tests/weird.mka"
        )

        XCTAssertTrue(vm.files.isEmpty)
        XCTAssertTrue(vm.selectedFileIDs.isEmpty)
        XCTAssertNotNil(vm.alertMessage, "the unsupported-format notice should surface")
        XCTAssertNil(vm.existingDownloadRowID(for: "https://example.com/exotic"))
    }

    // MARK: - Duplicate-URL dedupe

    func testExistingDownloadRowIDFindsRecordedRow() {
        let vm = makeViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )

        XCTAssertEqual(
            vm.existingDownloadRowID(for: "https://example.com/watch?v=abc"),
            vm.files[0].id
        )
        XCTAssertNil(vm.existingDownloadRowID(for: "https://example.com/other"))
    }

    func testDedupeForgetsRowsRemovedFromTheList() {
        let vm = makeViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )
        vm.clearAll()

        XCTAssertNil(vm.existingDownloadRowID(for: "https://example.com/watch?v=abc"),
                     "a removed row must not block re-downloading the same URL")
    }

    func testStartDownloadForDuplicateURLSelectsExistingRowInsteadOfDownloading() {
        let vm = makeViewModel()
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )
        let existingID = vm.files[0].id
        vm.selectedFileIDs = []

        vm.downloadURLField = "https://example.com/watch?v=abc"
        vm.isDownloadPopoverPresented = true
        vm.startDownload()

        XCTAssertEqual(vm.downloadState, .idle, "duplicate URL must not start a new download")
        XCTAssertEqual(vm.selectedFileIDs, [existingID])
        XCTAssertFalse(vm.isDownloadPopoverPresented)
    }

    // MARK: - A cleared download folder

    /// With no show folder to find a newer episode in, a folder that has gone
    /// stops the download instead of quietly using the default.
    func testAGoneFolderWithNoEpisodeToMoveToFailsWithoutFallingBack() {
        let vm = makeViewModel()
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-missing-\(UUID().uuidString)").path
        vm.settings.sessionRootPath = nil
        vm.settings.downloadDirectoryPath = absent
        vm.downloadURLField = "https://example.com/watch?v=abc"

        vm.startDownload()

        guard case .failed(let message) = vm.downloadState else {
            return XCTFail("expected a failure, got \(vm.downloadState)")
        }
        XCTAssertTrue(message.contains("is gone"), message)
        XCTAssertFalse(vm.isDownloading)
        XCTAssertEqual(vm.settings.downloadDirectoryPath, absent,
                       "it must not silently fall back to the default")
    }
}
