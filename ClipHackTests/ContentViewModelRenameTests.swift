import XCTest
@testable import ClipHack

@MainActor
final class ContentViewModelRenameTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rename-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("test".utf8).write(to: url)
        return url
    }

    private func makeViewModel(withFile url: URL) -> ContentViewModel {
        let vm = ContentViewModel()
        vm.files = [FileItem(url: url)]
        return vm
    }

    // MARK: - renameFile

    func testRenameMovesFileOnDiskAndUpdatesRow() throws {
        let original = try makeFile("clip one.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "better name"), .renamed)

        let renamed = tempDir.appendingPathComponent("better name.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(vm.files[0].url, renamed)
    }

    func testRenamePreservesExtensionAndSanitizesStem() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "a/b: c"), .renamed)
        XCTAssertEqual(vm.files[0].url.lastPathComponent, "a-b- c.m4a")
    }

    func testRenamePreservesComputedRowState() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)
        let stats = AudioStats(rms: -20, peak: -3, crest: 17, lufs: -19)
        vm.files[0].analysisStats = stats
        vm.files[0].notes = "keep me"
        vm.files[0].status = .ready(stats)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "renamed"), .renamed)

        XCTAssertEqual(vm.files[0].analysisStats, stats)
        XCTAssertEqual(vm.files[0].notes, "keep me")
        XCTAssertEqual(vm.files[0].status, .ready(stats))
    }

    func testRenameToInvalidNameIsRejected() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "   "), .invalidName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(vm.files[0].url, original)
    }

    func testRenameToTakenNameIsRejected() throws {
        let original = try makeFile("clip.m4a")
        _ = try makeFile("other.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "other"), .nameTaken)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(vm.files[0].url, original)
    }

    func testCaseOnlyRenameIsAllowed() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "Clip"), .renamed)
        XCTAssertEqual(vm.files[0].url.lastPathComponent, "Clip.m4a")
    }

    func testSameNameIsANoOpSuccess() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "clip"), .renamed)
        XCTAssertEqual(vm.files[0].url, original)
    }

    func testRenameWhileAnalyzingIsRefused() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)
        vm.files[0].status = .analyzing

        XCTAssertEqual(vm.renameFile(id: vm.files[0].id, to: "nope"), .notRenamable)
        XCTAssertEqual(vm.files[0].url, original)
    }

    // MARK: - Alert flow

    func testBeginRenamePrefillsStemAndGuardsBusyRows() throws {
        let original = try makeFile("clip one.m4a")
        let vm = makeViewModel(withFile: original)

        vm.beginRename(vm.files[0].id)
        XCTAssertEqual(vm.renameTargetID, vm.files[0].id)
        XCTAssertEqual(vm.renameField, "clip one")

        vm.cancelRename()
        vm.files[0].status = .processing
        vm.beginRename(vm.files[0].id)
        XCTAssertNil(vm.renameTargetID, "busy rows must not open the rename alert")
    }

    func testConfirmRenameFailureRoutesToNoticeAlert() throws {
        let original = try makeFile("clip.m4a")
        _ = try makeFile("other.m4a")
        let vm = makeViewModel(withFile: original)

        vm.beginRename(vm.files[0].id)
        vm.renameField = "other"
        vm.confirmRename()

        XCTAssertNil(vm.renameTargetID)
        XCTAssertEqual(vm.alertTitle, "Rename Failed")
        XCTAssertNotNil(vm.alertMessage)
        XCTAssertEqual(vm.files[0].url, original)
    }

    func testConfirmRenameSuccessClearsStateSilently() throws {
        let original = try makeFile("clip.m4a")
        let vm = makeViewModel(withFile: original)

        vm.beginRename(vm.files[0].id)
        vm.renameField = "fresh"
        vm.confirmRename()

        XCTAssertNil(vm.renameTargetID)
        XCTAssertNil(vm.alertMessage)
        XCTAssertEqual(vm.files[0].url.lastPathComponent, "fresh.m4a")
    }
}
