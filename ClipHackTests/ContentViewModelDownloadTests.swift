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
        XCTAssertFalse(vm.isDownloading, "a drop must never start the download by itself")
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

    func testStartDownloadWithInvalidFieldSetsErrorAndDoesNotRun() {
        let vm = makeViewModel()
        vm.downloadURLField = "not a url"
        vm.startDownload()

        XCTAssertNotNil(vm.downloadError)
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

        XCTAssertFalse(vm.isDownloading, "duplicate URL must not start a new download")
        XCTAssertEqual(vm.selectedFileIDs, [existingID])
        XCTAssertFalse(vm.isDownloadPopoverPresented)
    }
}
