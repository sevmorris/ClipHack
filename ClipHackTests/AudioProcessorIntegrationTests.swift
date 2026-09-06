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

    /// The claim per-file overrides make: one batch, one AudioProcessor, two
    /// clips that come out with different channel counts. If the override were
    /// still batch-wide these would agree, whatever the panel said.
    func testOneBatchHonoursDifferentChannelModesPerClip() async throws {
        let tools = try XCTUnwrap(tools)
        let stereoSource = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: tools.ffmpeg, directory: workDir, name: "a.wav",
            durationSeconds: 0.3, sampleRate: 44100, channels: 2
        )
        let otherSource = try IntegrationFFmpeg.makeSineWAV(
            ffmpeg: tools.ffmpeg, directory: workDir, name: "b.wav",
            durationSeconds: 0.3, sampleRate: 44100, channels: 2
        )

        // The panel says mono-left; one clip overrides to stereo.
        var settings = ClipHackSettings()
        settings.loudnormEnabled = false
        settings.stereoOutput = false
        settings.channel = .left
        settings.outputDirectoryPath = workDir.path

        let stereoID = UUID(), monoID = UUID()
        let batch = try await AudioProcessor(settings: settings).run(inputs: [
            JobInput(id: stereoID, url: stereoSource, channelMode: .stereo),
            JobInput(id: monoID, url: otherSource, channelMode: nil),
        ])

        XCTAssertEqual(batch.failures.count, 0, batch.failures.map(\.message).joined(separator: "; "))
        let stereoOut = try XCTUnwrap(batch.successes.first { $0.id == stereoID }?.output)
        let monoOut = try XCTUnwrap(batch.successes.first { $0.id == monoID }?.output)

        XCTAssertEqual(try channelCount(ffprobe: tools.ffprobe, url: stereoOut), 2,
                       "the clip that overrode to stereo stays stereo")
        XCTAssertEqual(try channelCount(ffprobe: tools.ffprobe, url: monoOut), 1,
                       "the clip with no override follows the panel")
    }

    /// Reads a file's channel count, so the assertions above are about the
    /// audio that was actually written rather than the arguments we passed.
    private func channelCount(ffprobe: String, url: URL) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels",
            "-of", "csv=p=0", url.path,
        ]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(text) ?? -1
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
