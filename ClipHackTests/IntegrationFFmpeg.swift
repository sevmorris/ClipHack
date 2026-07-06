import Foundation
import XCTest
@testable import ClipHackKit

enum IntegrationFFmpeg {
    static func locate() throws -> (ffmpeg: String, ffprobe: String) {
        let root = projectRoot()
        let ffmpeg = root.appendingPathComponent("ClipHackKit/ffmpeg")
        let ffprobe = root.appendingPathComponent("ClipHackKit/ffprobe")
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: ffmpeg.path),
              fm.isExecutableFile(atPath: ffprobe.path) else {
            throw XCTSkip("FFmpeg binaries missing — run ./scripts/fetch-ffmpeg.sh")
        }
        return (ffmpeg.path, ffprobe.path)
    }

    static func makeSineWAV(
        ffmpeg: String,
        directory: URL,
        name: String,
        durationSeconds: Double,
        sampleRate: Int,
        channels: Int = 1
    ) throws -> URL {
        let out = directory.appendingPathComponent(name)
        try run(ffmpeg: ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=\(durationSeconds)",
            "-ar", "\(sampleRate)", "-ac", "\(channels)",
            "-c:a", "pcm_s16le",
            out.path
        ])
        return out
    }

    static func run(ffmpeg: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "IntegrationFFmpeg", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: msg.isEmpty ? "ffmpeg exit \(process.terminationStatus)" : msg
            ])
        }
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
