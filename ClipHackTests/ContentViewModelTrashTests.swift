import XCTest
@testable import ClipHackKit

/// Covers the row bookkeeping around trashing. The trash operation is injected,
/// so nothing reaches the tester's real Trash.
@MainActor
final class ContentViewModelTrashTests: XCTestCase {

    private let input = URL(fileURLWithPath: "/tmp/clips/take.wav")
    private let output = URL(fileURLWithPath: "/tmp/clips/take-44kclipped-1dB.wav")

    private func makeViewModel(files: [FileItem]) -> ContentViewModel {
        let vm = ContentViewModel()
        vm.files = files
        return vm
    }

    func testMarksRowWhenOriginalIsTrashed() {
        let item = FileItem(url: input)
        let vm = makeViewModel(files: [item])

        let refusals = vm.trashOriginals(
            for: [JobResult(id: item.id, input: input, output: output)],
            trash: { _, _ in nil }
        )

        XCTAssertTrue(refusals.isEmpty)
        XCTAssertTrue(vm.files[0].originalTrashed)
    }

    /// An original that vanished on its own is still gone — the row should say so,
    /// and the user should not be told about it.
    func testTreatsMissingOriginalAsTrashedAndStaysSilent() {
        let item = FileItem(url: input)
        let vm = makeViewModel(files: [item])

        let refusals = vm.trashOriginals(
            for: [JobResult(id: item.id, input: input, output: output)],
            trash: { _, _ in .originalMissing }
        )

        XCTAssertTrue(refusals.isEmpty)
        XCTAssertTrue(vm.files[0].originalTrashed)
    }

    func testLeavesRowUnmarkedAndReportsWhenTrashFails() {
        let item = FileItem(url: input)
        let vm = makeViewModel(files: [item])

        let refusals = vm.trashOriginals(
            for: [JobResult(id: item.id, input: input, output: output)],
            trash: { _, _ in .trashFailed("The volume doesn't support a Trash.") }
        )

        XCTAssertEqual(refusals.count, 1)
        XCTAssertTrue(refusals[0].contains("take.wav"))
        XCTAssertTrue(refusals[0].contains("The volume doesn't support a Trash."))
        XCTAssertFalse(vm.files[0].originalTrashed, "The file is still on disk — the row must not claim otherwise.")
    }

    func testReportsWhenOutputCouldNotBeConfirmed() {
        let item = FileItem(url: input)
        let vm = makeViewModel(files: [item])

        let refusals = vm.trashOriginals(
            for: [JobResult(id: item.id, input: input, output: output)],
            trash: { _, _ in .outputNotUsable }
        )

        XCTAssertEqual(refusals.count, 1)
        XCTAssertTrue(refusals[0].contains("take.wav"))
        XCTAssertFalse(vm.files[0].originalTrashed)
    }

    /// One bad file must not stop the rest of the batch being tidied up.
    func testTrashesEveryRowIndependently() {
        let good = FileItem(url: URL(fileURLWithPath: "/tmp/clips/good.wav"))
        let bad = FileItem(url: URL(fileURLWithPath: "/tmp/clips/bad.wav"))
        let vm = makeViewModel(files: [good, bad])

        let refusals = vm.trashOriginals(
            for: [
                JobResult(id: good.id, input: good.url, output: output),
                JobResult(id: bad.id, input: bad.url, output: output)
            ],
            trash: { original, _ in
                original.lastPathComponent == "bad.wav" ? .trashFailed("nope") : nil
            }
        )

        XCTAssertEqual(refusals.count, 1)
        XCTAssertTrue(vm.files[0].originalTrashed)
        XCTAssertFalse(vm.files[1].originalTrashed)
    }

    func testIgnoresResultsWithNoMatchingRow() {
        let vm = makeViewModel(files: [])

        let refusals = vm.trashOriginals(
            for: [JobResult(id: UUID(), input: input, output: output)],
            trash: { _, _ in XCTFail("Should not trash a file with no row"); return nil }
        )

        XCTAssertTrue(refusals.isEmpty)
    }

    // MARK: - Preference

    /// The preference ships on. `UserDefaults.bool(forKey:)` returns false when a
    /// key is absent, so reading it that way would silently invert this default.
    func testTrashOriginalsDefaultsToOnWhenNeverSet() {
        let key = "trashOriginalsAfterProcessing"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(ContentViewModel().trashOriginalsEnabled)
    }

    func testTrashOriginalsPreferenceSurvivesAReload() {
        let key = "trashOriginalsAfterProcessing"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let vm = ContentViewModel()
        vm.trashOriginalsEnabled = false
        XCTAssertFalse(ContentViewModel().trashOriginalsEnabled)
    }

    // MARK: - Rename interaction

    func testTrashedOriginalIsNotRenamable() {
        var item = FileItem(url: input)
        item.originalTrashed = true
        let vm = makeViewModel(files: [item])

        XCTAssertFalse(vm.isRenamable(vm.files[0]), "There is nothing left at the row's path to rename.")
    }

    func testUntrashedRowStaysRenamable() {
        let vm = makeViewModel(files: [FileItem(url: input)])
        XCTAssertTrue(vm.isRenamable(vm.files[0]))
    }
}
