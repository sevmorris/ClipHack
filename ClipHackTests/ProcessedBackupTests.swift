import XCTest
@testable import ClipHackKit

final class ProcessedBackupTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("processed-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeOutput(_ name: String, contents: String = "audio") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testTheCopyGoesInAnOrigFolderBesideTheClip() throws {
        let output = try makeOutput("Talarico town hall .60 to end-44knorm-clipped-1dB.wav")

        let copy = try ProcessedBackup.copy(output)

        XCTAssertEqual(copy.deletingLastPathComponent().lastPathComponent, "orig")
        XCTAssertEqual(copy.lastPathComponent, output.lastPathComponent, "the same name, cut and all")
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: output))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "the clip itself stays")
    }

    /// Cutting the clip must leave the copy as it was.
    func testTheCopyIsIndependentOfTheClip() throws {
        let output = try makeOutput("Clip-44kclipped-1dB.wav", contents: "uncut")
        let copy = try ProcessedBackup.copy(output)

        try Data("cut".utf8).write(to: output)

        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "uncut")
    }

    func testAnEarlierCopyIsNeverOverwritten() throws {
        let output = try makeOutput("Clip-44kclipped-1dB.wav", contents: "second")
        let orig = dir.appendingPathComponent("orig", isDirectory: true)
        try FileManager.default.createDirectory(at: orig, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: orig.appendingPathComponent("Clip-44kclipped-1dB.wav"))

        let copy = try ProcessedBackup.copy(output)

        XCTAssertEqual(copy.lastPathComponent, "Clip-44kclipped-1dB (1).wav")
        XCTAssertEqual(try String(contentsOf: orig.appendingPathComponent("Clip-44kclipped-1dB.wav"), encoding: .utf8), "first")
    }
}
