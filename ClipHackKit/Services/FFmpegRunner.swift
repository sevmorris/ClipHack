@preconcurrency import Foundation

/// ffmpeg/ffprobe invocations for ClipHack: timeout policy, exit-code handling,
/// and the parsers for what the filters print. Running the process itself is
/// `FFmpegProcess`, which is shared verbatim with the sibling app repos and
/// knows nothing about any of this.
enum FFmpegRunner {
    static func run(exe: String, args: [String]) async throws {
        let (exitCode, stderr) = try await FFmpegProcess.launch(
            exe: exe, args: args, capture: .stderr, timeoutSeconds: processTimeoutSeconds
        )
        if exitCode != 0 {
            throw ProcessingError.ffmpegFailed(
                code: exitCode,
                message: stderr.isEmpty ? "Exit code \(exitCode)" : stderr
            )
        }
    }

    static func capture(exe: String, args: [String]) async throws -> String {
        let (exitCode, stderr) = try await FFmpegProcess.launch(
            exe: exe, args: args, capture: .stderr, timeoutSeconds: processTimeoutSeconds
        )
        if exitCode != 0 {
            throw ProcessingError.ffmpegFailed(
                code: exitCode,
                message: stderr.isEmpty ? "Exit code \(exitCode)" : stderr
            )
        }
        return stderr
    }

    static func captureStdout(exe: String, args: [String]) async throws -> String {
        let (exitCode, stdout) = try await FFmpegProcess.launch(
            exe: exe, args: args, capture: .stdout, timeoutSeconds: processTimeoutSeconds
        )
        if exitCode != 0 {
            throw ProcessingError.ffmpegFailed(
                code: exitCode,
                message: stdout.isEmpty ? "Exit code \(exitCode)" : stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return stdout
    }

    nonisolated static func parseLoudnormJSON(from output: String) -> [String: String]? {
        let searchStart: String.Index
        if let prefixRange = output.range(of: "[Parsed_loudnorm_", options: .backwards) {
            searchStart = prefixRange.upperBound
        } else {
            searchStart = output.startIndex
        }
        guard let braceRange = output.range(of: "{", range: searchStart..<output.endIndex) else { return nil }

        var depth = 0
        var jsonEnd: String.Index?
        outer: for idx in output[braceRange.lowerBound...].indices {
            switch output[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { jsonEnd = idx; break outer }
            default: break
            }
        }

        guard let jsonEnd else { return nil }

        let jsonStr = String(output[braceRange.lowerBound...jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else {
            return nil
        }

        var result: [String: String] = [:]
        for (key, value) in dict {
            if let s = value as? String {
                result[key] = s
            } else if let n = value as? NSNumber {
                result[key] = n.stringValue
            }
        }
        return result.isEmpty ? nil : result
    }

    nonisolated static func loudnormMeasurementsAreFinite(_ json: [String: String]) -> Bool {
        let keys = ["input_i", "input_tp", "input_lra", "input_thresh", "target_offset"]
        for key in keys {
            guard let raw = json[key], let value = Double(raw), value.isFinite else { return false }
        }
        return true
    }

    /// Watchdog ceiling for one ffmpeg invocation. ClipHack handles short clips,
    /// so a flat ceiling is adequate; a per-file proportional timeout would only
    /// matter for long-form input.
    nonisolated static let processTimeoutSeconds: Int = 900
}
