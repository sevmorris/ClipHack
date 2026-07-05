import XCTest
@testable import ClipHackKit

/// FFmpeg integration tests — require bundled binaries (run `./scripts/fetch-ffmpeg.sh` first).
final class AudioProcessorIntegrationTests: XCTestCase {

    private var tools: (ffmpeg: String, ffprobe: String)?
    private var workDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tools = try IntegrationFFmpeg.locate()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
        try super.tearDownWithError()
    }

    func testProducesNonEmptyWAV() async throws {
        let tools = try XCTUnwrap(tools)
        let input = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: tools.ffmpeg,
            directory: workDir,
            name: "input.wav",
            durationSeconds: 0.5,
            sampleRate: 44100
        )

        var settings = ClipHackSettings()
        settings.loudnormEnabled = false
        settings.outputDirectoryPath = workDir.path

        let processor = AudioProcessor(settings: settings)
        let batch = try await processor.run(inputs: [JobInput(id: UUID(), url: input)])

        XCTAssertEqual(batch.failures.count, 0, batch.failures.map(\.message).joined(separator: "; "))
        let result = try XCTUnwrap(batch.successes.first)
        let attrs = try FileManager.default.attributesOfItem(atPath: result.output.path)
        let size = try XCTUnwrap(attrs[.size] as? NSNumber)
        XCTAssertGreaterThan(size.intValue, 1000)
        XCTAssertTrue(result.output.lastPathComponent.contains("clipped"))
    }

    func testLoudnormTwoPassAt48kHz() async throws {
        let tools = try XCTUnwrap(tools)
        let input = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: tools.ffmpeg,
            directory: workDir,
            name: "loudnorm_in.wav",
            durationSeconds: 6.0,
            sampleRate: 48000
        )

        var settings = ClipHackSettings()
        settings.sampleRate = .s48000
        settings.loudnormEnabled = true
        settings.loudnormTarget = -23.0
        settings.outputDirectoryPath = workDir.path

        let processor = AudioProcessor(settings: settings)
        let batch = try await processor.run(inputs: [JobInput(id: UUID(), url: input)])

        XCTAssertEqual(batch.failures.count, 0, batch.failures.map(\.message).joined(separator: "; "))
        let output = try XCTUnwrap(batch.successes.first?.output)

        let measuredI = try await measureIntegratedLoudness(ffmpeg: tools.ffmpeg, of: output)
        XCTAssertEqual(measuredI, settings.loudnormTarget, accuracy: 2.0)
    }

    private func measureIntegratedLoudness(ffmpeg: String, of url: URL) async throws -> Double {
        let stderr = try await FFmpegRunner.capture(exe: ffmpeg, args: [
            "-nostdin", "-hide_banner",
            "-i", url.path,
            "-af", "loudnorm=I=-23:TP=-1:LRA=20:print_format=json",
            "-f", "null", "/dev/null"
        ])
        let dict = try XCTUnwrap(FFmpegRunner.parseLoudnormJSON(from: stderr))
        return try XCTUnwrap(Double(dict["input_i"] ?? ""))
    }
}
