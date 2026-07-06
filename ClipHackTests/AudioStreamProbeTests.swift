import XCTest
@testable import ClipHackKit

final class AudioStreamProbeTests: XCTestCase {

    private var tools: (ffmpeg: String, ffprobe: String)?
    private var workDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let ffmpeg = root.appendingPathComponent("ClipHackKit/ffmpeg")
        let ffprobe = root.appendingPathComponent("ClipHackKit/ffprobe")
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: ffmpeg.path),
              fm.isExecutableFile(atPath: ffprobe.path) else {
            throw XCTSkip("FFmpeg binaries missing — run ./scripts/fetch-ffmpeg.sh")
        }
        tools = (ffmpeg.path, ffprobe.path)
        workDir = fm.temporaryDirectory.appendingPathComponent("cliphack-probe-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
        try super.tearDownWithError()
    }

    func testHasAudioStreamOnWAV() async throws {
        let (ffmpeg, ffprobe) = try XCTUnwrap(tools)
        let wav = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: ffmpeg,
            directory: workDir,
            name: "tone.wav",
            durationSeconds: 0.25,
            sampleRate: 44100
        )
        let ok = await AudioStreamProbe.hasAudioStream(ffprobe: ffprobe, url: wav)
        XCTAssertTrue(ok)
    }

    func testHasAudioStreamRejectsTextFile() async throws {
        let (_, ffprobe) = try XCTUnwrap(tools)
        let txt = workDir.appendingPathComponent("not-audio.txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        let ok = await AudioStreamProbe.hasAudioStream(ffprobe: ffprobe, url: txt)
        XCTAssertFalse(ok)
    }
}
