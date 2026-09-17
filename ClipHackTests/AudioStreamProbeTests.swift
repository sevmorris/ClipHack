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

    func testProbeFindsAudioInWAV() async throws {
        let (ffmpeg, ffprobe) = try XCTUnwrap(tools)
        let wav = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: ffmpeg,
            directory: workDir,
            name: "tone.wav",
            durationSeconds: 0.25,
            sampleRate: 44100
        )
        let outcome = try await AudioStreamProbe.probe(ffprobe: ffprobe, url: wav)
        XCTAssertEqual(outcome, .audio)
        XCTAssertNil(outcome.failure)
    }

    func testProbeReportsNoAudioForTextFile() async throws {
        let (_, ffprobe) = try XCTUnwrap(tools)
        let txt = workDir.appendingPathComponent("not-audio.txt")
        try "hello".write(to: txt, atomically: true, encoding: .utf8)
        let outcome = try await AudioStreamProbe.probe(ffprobe: ffprobe, url: txt)
        XCTAssertEqual(outcome, .noAudio)
    }
}

/// An ffprobe that cannot run is a fault in the app, not in the file, and must
/// not be reported as "No audio stream found". None of these need the real
/// binaries, so they run even where FFmpeg has not been fetched.
final class AudioStreamProbeFailureTests: XCTestCase {

    private var workDir: URL!
    private var input: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fm = FileManager.default
        workDir = fm.temporaryDirectory.appendingPathComponent("cliphack-probe-fail-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        input = workDir.appendingPathComponent("clip.wav")
        try Data().write(to: input)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
        try super.tearDownWithError()
    }

    /// A stand-in ffprobe that runs `body` as a shell script.
    private func fakeProbe(_ body: String) throws -> String {
        let script = workDir.appendingPathComponent("ffprobe-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    func testMissingProbeIsAProbeFailure() async throws {
        let missing = workDir.appendingPathComponent("no-such-ffprobe").path
        let outcome = try await AudioStreamProbe.probe(ffprobe: missing, url: input)
        guard case .probeFailed = outcome else {
            return XCTFail("expected probeFailed, got \(outcome)")
        }
    }

    /// What dyld does to a binary without LC_UUID on macOS 26.7: SIGABRT
    /// before main.
    func testCrashingProbeIsAProbeFailure() async throws {
        let crashing = try fakeProbe("kill -ABRT $$")
        let outcome = try await AudioStreamProbe.probe(ffprobe: crashing, url: input)
        guard case .probeFailed(let detail) = outcome else {
            return XCTFail("expected probeFailed, got \(outcome)")
        }
        XCTAssertTrue(detail.contains("signal"), detail)
    }

    /// A non-zero exit of ffprobe's own is it refusing the file.
    func testRefusingProbeReportsNoAudio() async throws {
        let refusing = try fakeProbe("exit 1")
        let outcome = try await AudioStreamProbe.probe(ffprobe: refusing, url: input)
        XCTAssertEqual(outcome, .noAudio)
    }

    func testProbeFailureMessageDoesNotBlameTheFile() {
        let noAudio = AudioStreamProbe.Outcome.noAudio.failure?.errorDescription ?? ""
        let broken = AudioStreamProbe.Outcome.probeFailed("ffmpeg crashed (signal 6)").failure?.errorDescription ?? ""
        XCTAssertTrue(noAudio.contains("No audio stream found"), noAudio)
        XCTAssertFalse(broken.contains("No audio stream"), broken)
        XCTAssertTrue(broken.contains("ffmpeg crashed (signal 6)"), broken)
    }
}
