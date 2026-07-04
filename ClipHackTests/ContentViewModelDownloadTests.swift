import XCTest
@testable import ClipHack

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
}
