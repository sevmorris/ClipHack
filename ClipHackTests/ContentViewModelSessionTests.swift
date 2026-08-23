import XCTest
@testable import ClipHackKit

@MainActor
final class ContentViewModelSessionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        ScratchDefaults.install()
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

    private let aug24 = Date(timeIntervalSince1970: 1_787_529_600)

    // MARK: - Opening

    func testOpeningASessionPointsBothFoldersAtIt() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        let vm = makeViewModel()

        vm.openSession(session)

        XCTAssertEqual(vm.settings.downloadDirectoryPath, session.clipsFolder.path)
        XCTAssertEqual(vm.settings.outputDirectoryPath, session.clipsFolder.path,
                       "an episode's sources and its finished audio belong together")
    }

    func testSessionTitleFollowsTheOpenSession() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        let vm = makeViewModel()
        XCTAssertEqual(vm.sessionTitle, "ClipHack", "no session yet")

        vm.openSession(session)
        XCTAssertEqual(vm.sessionTitle, "HT_0380 2026-08-24")
        XCTAssertEqual(vm.currentSession?.folder.lastPathComponent, "HT_0380 2026-08-24")
    }

    func testOpeningASessionLoadsItsClipList() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        let clipFolder = session.clipsFolder.appendingPathComponent("Some Clip", isDirectory: true)
        try FileManager.default.createDirectory(at: clipFolder, withIntermediateDirectories: true)
        let audio = clipFolder.appendingPathComponent("Some Clip.m4a")
        try Data("audio".utf8).write(to: audio)
        try ClipNotesFile.write(notes: "TRUMP — said it", sourceURL: "https://a", forAudioFile: audio)

        let vm = makeViewModel()
        vm.openSession(session)

        XCTAssertEqual(vm.clipListRows.count, 1)
        XCTAssertEqual(vm.clipListRows.first?.person, "TRUMP")
        XCTAssertEqual(vm.clipListText, "1) TRUMP said it")
    }

    // MARK: - Creating

    func testCreatingASessionMakesTheFolderAndSwitchesToIt() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.createSession(title: "HT_0380 2026-08-24"))

        let clips = root
            .appendingPathComponent("HT_0380 2026-08-24", isDirectory: true)
            .appendingPathComponent("clips", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clips.path))
        XCTAssertEqual(vm.settings.downloadDirectoryPath, clips.path)
        XCTAssertEqual(vm.sessionTitle, "HT_0380 2026-08-24")
    }

    func testCreatingRefusesABlankTitle() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.createSession(title: "   "))
    }

    func testCreatingNeedsAShowRoot() {
        let vm = ContentViewModel()
        vm.settings.sessionRootPath = nil
        XCTAssertFalse(vm.createSession(title: "HT_0380 2026-08-24"))
        XCTAssertEqual(vm.alertTitle, "Choose a Show Folder")
    }

    // MARK: - Suggested name

    func testSuggestedTitleIncrementsFromWhatIsOnDisk() throws {
        try ClipSessionStore.create(title: "HT_0379 2026-08-17", inRoot: root)
        let vm = makeViewModel()
        vm.now = { [aug24] in aug24 }
        XCTAssertEqual(
            vm.suggestedSessionTitle,
            "HT_0380 \(ClipSessionStore.dateString(aug24))"
        )
    }

    // MARK: - Listing

    func testSessionsAreListedFromTheShowRoot() throws {
        try ClipSessionStore.create(title: "HT_0378 2026-08-10", inRoot: root)
        try ClipSessionStore.create(title: "HT_0379 2026-08-17", inRoot: root)
        let vm = makeViewModel()
        vm.loadSessions()
        XCTAssertEqual(vm.savedSessions.map(\.title), ["HT_0379 2026-08-17", "HT_0378 2026-08-10"])
    }

    func testShowRootIsAdoptedFromAHandPickedFolder() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
        let vm = ContentViewModel()
        vm.settings.sessionRootPath = nil
        vm.downloadDirectoryPicker = { session.clipsFolder.path }

        XCTAssertTrue(vm.chooseDownloadDirectory())
        XCTAssertEqual(vm.settings.sessionRootPath, root.standardizedFileURL.path,
                       "picking an episode's clips folder should adopt the show folder above it")
    }

    // MARK: - Presets must not move folders

    func testApplyingAPresetKeepsEveryFolderTheUserChose() throws {
        let session = try ClipSessionStore.create(title: "HT_0380 2026-08-24", inRoot: root)
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
}
