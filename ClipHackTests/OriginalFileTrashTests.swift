import XCTest
@testable import ClipHackKit

/// The real `trashItem` is injected out of every test here — these assert the
/// policy (what may be trashed, and when), without moving anything to the
/// tester's actual Trash.
final class OriginalFileTrashTests: XCTestCase {

    private let original = URL(fileURLWithPath: "/tmp/clips/take.wav")
    private let output = URL(fileURLWithPath: "/tmp/clips/take-44kclipped-1dB.wav")

    /// Records what was handed to `trashItem`, so a refusal can be told apart
    /// from a trash that silently succeeded.
    private final class Recorder {
        var trashed: [URL] = []
    }

    private func run(
        original: URL,
        output: URL,
        existing: Set<String>,
        sizes: [String: Int] = [:],
        throwing error: Error? = nil,
        recorder: Recorder = Recorder()
    ) -> (refusal: OriginalFileTrash.Refusal?, trashed: [URL]) {
        let refusal = OriginalFileTrash.trash(
            original: original,
            output: output,
            fileExists: { existing.contains($0.path) },
            fileSize: { sizes[$0.path] ?? 1024 },
            trashItem: { url in
                if let error { throw error }
                recorder.trashed.append(url)
            }
        )
        return (refusal, recorder.trashed)
    }

    func testTrashesOriginalWhenOutputIsPresentAndNonEmpty() {
        let result = run(
            original: original,
            output: output,
            existing: [original.path, output.path]
        )
        XCTAssertNil(result.refusal)
        XCTAssertEqual(result.trashed, [original])
    }

    func testKeepsOriginalWhenOutputIsMissing() {
        let result = run(original: original, output: output, existing: [original.path])
        XCTAssertEqual(result.refusal, .outputNotUsable)
        XCTAssertTrue(result.trashed.isEmpty, "The source is still the only copy — it must survive.")
    }

    func testKeepsOriginalWhenOutputIsZeroBytes() {
        let result = run(
            original: original,
            output: output,
            existing: [original.path, output.path],
            sizes: [output.path: 0]
        )
        XCTAssertEqual(result.refusal, .outputNotUsable)
        XCTAssertTrue(result.trashed.isEmpty)
    }

    func testReportsMissingOriginalWithoutTrashing() {
        let result = run(original: original, output: output, existing: [output.path])
        XCTAssertEqual(result.refusal, .originalMissing)
        XCTAssertTrue(result.trashed.isEmpty)
    }

    /// Guards the one case that would destroy the result of the run.
    func testNeverTrashesTheOutputItself() {
        let result = run(original: original, output: original, existing: [original.path])
        XCTAssertEqual(result.refusal, .outputIsOriginal)
        XCTAssertTrue(result.trashed.isEmpty)
    }

    /// Two spellings of one path must not read as "different file, safe to trash".
    func testTreatsUnstandardizedOutputPathAsTheSameFile() {
        let awkward = URL(fileURLWithPath: "/tmp/clips/../clips/./take.wav")
        let result = run(original: original, output: awkward, existing: [original.path])
        XCTAssertEqual(result.refusal, .outputIsOriginal)
        XCTAssertTrue(result.trashed.isEmpty)
    }

    func testSurfacesVolumeRefusalAsTrashFailed() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFeatureUnsupportedError,
            userInfo: [NSLocalizedDescriptionKey: "The volume doesn't support a Trash."]
        )
        let result = run(
            original: original,
            output: output,
            existing: [original.path, output.path],
            throwing: error
        )
        XCTAssertEqual(result.refusal, .trashFailed("The volume doesn't support a Trash."))
        XCTAssertTrue(result.trashed.isEmpty)
    }
}
