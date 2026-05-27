@preconcurrency import Foundation

enum FFmpegRunner {
    static func run(exe: String, args: [String]) async throws {
        let (exitCode, stderr) = try await launch(exe: exe, args: args, capture: .stderr)
        if exitCode != 0 {
            throw ProcessingError.ffmpegFailed(
                code: exitCode,
                message: stderr.isEmpty ? "Exit code \(exitCode)" : stderr
            )
        }
    }

    static func capture(exe: String, args: [String]) async throws -> String {
        let (exitCode, stderr) = try await launch(exe: exe, args: args, capture: .stderr)
        if exitCode != 0 {
            throw ProcessingError.ffmpegFailed(
                code: exitCode,
                message: stderr.isEmpty ? "Exit code \(exitCode)" : stderr
            )
        }
        return stderr
    }

    static func captureStdout(exe: String, args: [String]) async throws -> String {
        let (exitCode, stdout) = try await launch(exe: exe, args: args, capture: .stdout)
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

    private enum CaptureTarget { case stderr, stdout }

    private static func launch(
        exe: String,
        args: [String],
        capture: CaptureTarget
    ) async throws -> (Int32, String) {
        guard FileManager.default.fileExists(atPath: exe) else {
            throw ProcessingError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, String), Error>) in
                let pipe = Pipe()
                switch capture {
                case .stderr:
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = pipe
                case .stdout:
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                }

                final class DataBox: @unchecked Sendable { var value = Data() }
                let box = DataBox()
                let readGroup = DispatchGroup()
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    box.value = pipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                let timeoutItem = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 900, execute: timeoutItem)

                process.terminationHandler = { proc in
                    timeoutItem.cancel()
                    readGroup.wait()
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let msg = String(data: box.value, encoding: .utf8) ?? ""
                    continuation.resume(returning: (proc.terminationStatus, msg))
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(
                        code: -1,
                        message: "Failed to launch: \(error.localizedDescription)"
                    ))
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
