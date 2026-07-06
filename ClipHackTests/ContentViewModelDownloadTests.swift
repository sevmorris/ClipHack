import XCTest
@testable import ClipHackKit

@MainActor
final class ContentViewModelDownloadTests: XCTestCase {

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

    // MARK: - Notes and clip list

    func testFinishDownloadAttachesTrimmedNotesToRow() {
        let vm = makeViewModel()
        vm.downloadNotesField = "  :30 to :12  "
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )

        XCTAssertEqual(vm.files[0].notes, ":30 to :12")
        XCTAssertEqual(vm.downloadNotesField, "", "notes clear once they're on the row")
    }

    func testEmptyNotesLeaveRowNotesNil() {
        let vm = makeViewModel()
        vm.downloadNotesField = "   "
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: "/tmp/cliphack-tests/Title.m4a"
        )
        XCTAssertNil(vm.files[0].notes)
    }

    func testClipListWrittenNextToDownloadWhenEnabled() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-vm-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel()
        let wasEnabled = vm.clipListEnabled
        defer { vm.clipListEnabled = wasEnabled }
        vm.clipListEnabled = true
        vm.downloadNotesField = "the good part"
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )

        let manifestURL = dir.appendingPathComponent(ClipListManifest.manifestFilename())
        let content = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertEqual(content, "Title.m4a\nthe good part\nhttps://example.com/watch?v=abc\n\n")
    }

    func testClipListSkippedWhenDisabled() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-vm-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel()
        let wasEnabled = vm.clipListEnabled
        defer { vm.clipListEnabled = wasEnabled }
        vm.clipListEnabled = false
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )

        let manifestURL = dir.appendingPathComponent(ClipListManifest.manifestFilename())
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testDuplicateURLWritesNoClipListEntry() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-vm-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel()
        let wasEnabled = vm.clipListEnabled
        defer { vm.clipListEnabled = wasEnabled }
        vm.clipListEnabled = true
        vm.finishDownload(
            sourceURL: "https://example.com/watch?v=abc",
            filePath: dir.appendingPathComponent("Title.m4a").path
        )
        let manifestURL = dir.appendingPathComponent(ClipListManifest.manifestFilename())
        let afterFirst = try String(contentsOf: manifestURL, encoding: .utf8)

        vm.downloadURLField = "https://example.com/watch?v=abc"
        vm.downloadNotesField = "should not be logged"
        vm.startDownload()

        XCTAssertEqual(try String(contentsOf: manifestURL, encoding: .utf8), afterFirst,
                       "a duplicate-URL selection downloads nothing and logs nothing")
        XCTAssertEqual(vm.downloadNotesField, "", "duplicate path clears the notes field")
    }

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

    // MARK: - X-post Notes prefill
    //
    // The fill/stale guards are tested synchronously through applyFetchedNotes;
    // the trigger points are tested by whether a fetch task is spawned. Awaiting
    // the fire-and-forget task from an async XCTest method corrupts the test
    // harness's task allocator, so it's deliberately avoided here.

    private let xURL = "https://x.com/atrupar/status/2073253157933666426"

    func testApplyFillsEmptyNotesForMatchingURL() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.applyFetchedNotes("fetched post body", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "fetched post body")
    }

    func testApplyDoesNotClobberTypedNotes() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadNotesField = "my own note"
        vm.applyFetchedNotes("fetched post body", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "my own note", "fill-if-empty must not overwrite typed notes")
    }

    func testApplySkipsWhenURLFieldChanged() {
        let vm = makeViewModel()
        vm.downloadURLField = "https://x.com/other/status/999"
        vm.applyFetchedNotes("fetched post body", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "", "stale-URL result must not be applied")
    }

    func testApplyIgnoresNilOrEmptyText() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.applyFetchedNotes(nil, for: xURL)
        vm.applyFetchedNotes("   ", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "")
    }

    func testPrefillSpawnsFetchTaskForXPostURL() {
        let vm = makeViewModel()
        vm.prefillNotesFromURL(xURL)
        XCTAssertNotNil(vm.notesFetchTask, "an X post URL should spawn a fetch")
        vm.notesFetchTask?.cancel()
    }

    func testPrefillSpawnsNoTaskForNonXURL() {
        let vm = makeViewModel()
        vm.prefillNotesFromURL("https://youtu.be/abc123")
        XCTAssertNil(vm.notesFetchTask, "non-X URLs must not spawn a fetch")
    }

    func testAcceptDroppedXURLSpawnsNotesPrefill() {
        let vm = makeViewModel()
        vm.acceptDroppedURL(xURL)
        XCTAssertNotNil(vm.notesFetchTask)
        vm.notesFetchTask?.cancel()
    }

    // MARK: - URL-field change triggers the fetch (paste, not just Return)

    private let otherXURL = "https://x.com/someone/status/1234567890123456789"

    func testURLFieldChangeSpawnsFetchForPastedXURL() {
        let vm = makeViewModel()
        // Simulate a paste straight into the field (no Return): the binding
        // mutates, then onChange calls downloadURLFieldChanged.
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        XCTAssertNotNil(vm.notesFetchTask, "pasting a valid X post URL must trigger the notes fetch")
        vm.notesFetchTask?.cancel()
    }

    func testURLFieldChangeSpawnsNoFetchForNonXURL() {
        let vm = makeViewModel()
        vm.downloadURLField = "https://youtu.be/abc123"
        vm.downloadURLFieldChanged()
        XCTAssertNil(vm.notesFetchTask, "a non-X URL must not spawn a fetch")
    }

    func testURLFieldChangeDoesNotFetchWhileTypingProfileURL() {
        let vm = makeViewModel()
        // Mid-typing an X URL that isn't yet a /status/ link: no fetch.
        vm.downloadURLField = "https://x.com/atrupar"
        vm.downloadURLFieldChanged()
        XCTAssertNil(vm.notesFetchTask, "a non-status X URL (still typing) must not fetch")
    }

    func testEditingSameStatusURLKeepsNotesAndDoesNotRefire() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        vm.applyFetchedNotes("post body", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "post body")

        // Tweak the URL but keep the same status ID (add a tracking param).
        vm.downloadURLField = xURL + "?s=46"
        vm.downloadURLFieldChanged()
        XCTAssertEqual(vm.downloadNotesField, "post body",
                       "same post: dedupe must keep the notes and not refetch")
        vm.notesFetchTask?.cancel()
    }

    // MARK: - Stale auto-filled notes refresh; user-edited notes never do

    func testChangingToNewPostClearsPreviousAutoFilledNotes() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        vm.applyFetchedNotes("first post body", for: xURL)
        XCTAssertEqual(vm.downloadNotesField, "first post body")

        // Paste a different X post URL — the stale auto-filled notes must go and
        // a fresh fetch must start for the new post.
        vm.downloadURLField = otherXURL
        vm.downloadURLFieldChanged()
        XCTAssertEqual(vm.downloadNotesField, "",
                       "auto-filled notes from the previous post must clear for a new post")
        XCTAssertNotNil(vm.notesFetchTask, "the new post should trigger its own fetch")

        // And the new post's fetch fills the now-empty field.
        vm.applyFetchedNotes("second post body", for: otherXURL)
        XCTAssertEqual(vm.downloadNotesField, "second post body")
        vm.notesFetchTask?.cancel()
    }

    func testChangingURLNeverClearsUserEditedNotes() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        vm.applyFetchedNotes("auto body", for: xURL)

        // The user edits the auto-filled notes into their own text.
        vm.downloadNotesField = "my own note"

        // Switching to a different post must NOT touch the user's text …
        vm.downloadURLField = otherXURL
        vm.downloadURLFieldChanged()
        XCTAssertEqual(vm.downloadNotesField, "my own note",
                       "user-edited notes must never be cleared by a URL change")

        // … and the new fetch must not clobber it either.
        vm.applyFetchedNotes("second post body", for: otherXURL)
        XCTAssertEqual(vm.downloadNotesField, "my own note",
                       "the fill-if-empty guard must still protect user notes")
        vm.notesFetchTask?.cancel()
    }

    func testClearingURLClearsStaleAutoFilledNotes() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        vm.applyFetchedNotes("post body", for: xURL)

        vm.downloadURLField = ""
        vm.downloadURLFieldChanged()
        XCTAssertEqual(vm.downloadNotesField, "",
                       "clearing the URL should drop notes a previous auto-fill left behind")
    }

    func testChangingToNonXURLKeepsUserEditedNotes() {
        let vm = makeViewModel()
        vm.downloadURLField = xURL
        vm.downloadURLFieldChanged()
        vm.applyFetchedNotes("auto body", for: xURL)
        vm.downloadNotesField = "my own note"

        vm.downloadURLField = "https://youtu.be/abc123"
        vm.downloadURLFieldChanged()
        XCTAssertEqual(vm.downloadNotesField, "my own note",
                       "moving to a non-X URL must not clear the user's own notes")
    }

    // MARK: - Missing custom download folder re-prompt

    func testStartDownloadCancelledRePromptFailsWithoutFallback() {
        let vm = makeViewModel()
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-missing-\(UUID().uuidString)").path
        vm.settings.downloadDirectoryPath = absent
        vm.downloadDirectoryPicker = { nil }   // user cancels the re-prompt
        vm.downloadURLField = "https://example.com/watch?v=abc"

        vm.startDownload()

        XCTAssertEqual(vm.downloadState, .failed("Choose a destination folder to download."))
        XCTAssertFalse(vm.isDownloading, "a cancelled re-prompt must not start a download")
        XCTAssertEqual(vm.settings.downloadDirectoryPath, absent,
                       "cancelling must not silently fall back to the default")
    }

    func testStartDownloadRePromptPicksNewFolderAndClearsStaleFailure() {
        let vm = makeViewModel()
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-missing-\(UUID().uuidString)").path
        let picked = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-picked-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: picked) }
        vm.settings.downloadDirectoryPath = absent
        // User picks a new, valid (existing) folder at the re-prompt.
        vm.downloadDirectoryPicker = { picked.path }

        XCTAssertTrue(vm.chooseDownloadDirectory())
        XCTAssertEqual(vm.settings.downloadDirectoryPath, picked.path,
                       "picking a new folder persists it as the destination")
        XCTAssertFalse(YtDlpService.customDownloadDirectoryMissing(vm.settings.downloadDirectoryPath),
                       "the newly-picked folder must resolve as present")
    }
}
