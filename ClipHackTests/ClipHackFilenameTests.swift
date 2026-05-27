import XCTest
@testable import ClipHack

final class ClipHackFilenameTests: XCTestCase {

    func testFormatDbTag() {
        XCTAssertEqual(ClipHackFilename.formatDbTag(-1.0), "1dB")
        XCTAssertEqual(ClipHackFilename.formatDbTag(-1.50), "1.5dB")
    }

    func testUniqueOutputURLAppendsCounter() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let base = dir.appendingPathComponent("clip-44kclipped-1dB.wav")
        fm.createFile(atPath: base.path, contents: Data([0x00]))

        let unique = ClipHackFilename.uniqueOutputURL(base, fm: fm)
        XCTAssertTrue(unique.lastPathComponent.contains("(1)"))
    }
}
