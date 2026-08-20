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

    /// Watchdog ceiling for one ffmpeg invocation. ClipHack handles short clips,
    /// so a flat ceiling is adequate; a per-file proportional timeout would only
    /// matter for long-form input.
    nonisolated static let processTimeoutSeconds: Int = 900

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

        // Set before any terminate() we issue ourselves, so the termination
        // handler can tell a deliberate cancel from an ffmpeg crash: FFmpeg
        // catches SIGTERM and exits normally with code 255, so terminationReason
        // alone cannot distinguish them.
        let cancelFlag = TimeoutFlag()

        // Set only once process.run() has returned without throwing. Guards every
        // terminate() call site — terminating a Process that was never launched
        // raises NSInvalidArgumentException, which Swift cannot catch.
        let launchFlag = TimeoutFlag()

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

                // nonisolated: the box is captured by the pipe-reader closure on a
                // utility queue and by the termination handler, so its last release
                // lands off-task — where an implicit MainActor deinit malloc-aborts
                // in macOS 15's isolated-deinit runtime.
                nonisolated final class DataBox: @unchecked Sendable { var value = Data() }
                let box = DataBox()
                let readGroup = DispatchGroup()
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    box.value = pipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                let timeoutFlag = TimeoutFlag()
                let timeoutItem = DispatchWorkItem {
                    timeoutFlag.set()
                    if launchFlag.didFire { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + .seconds(processTimeoutSeconds),
                    execute: timeoutItem
                )

                process.terminationHandler = { proc in
                    timeoutItem.cancel()
                    readGroup.wait()
                    if timeoutFlag.didFire {
                        continuation.resume(throwing: ProcessingError.ffmpegFailed(
                            code: -1,
                            message: "ffmpeg timed out after \(processTimeoutSeconds) seconds"
                        ))
                        return
                    }
                    if cancelFlag.didFire {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    // Not cancelled by us, so an unexpected signal is an ffmpeg
                    // crash (SIGSEGV, SIGABRT, OOM SIGKILL). Reporting those as
                    // CancellationError silently aborted the batch with no error.
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: ProcessingError.ffmpegFailed(
                            code: proc.terminationStatus,
                            message: "ffmpeg crashed (signal \(proc.terminationStatus))"
                        ))
                        return
                    }
                    let msg = String(data: box.value, encoding: .utf8) ?? ""
                    continuation.resume(returning: (proc.terminationStatus, msg))
                }

                do {
                    try process.run()
                    launchFlag.set()
                    // Closes the race where onCancel ran between its launchFlag
                    // check and this set(): it saw the flag unset and skipped the
                    // terminate, so we issue it here instead.
                    if cancelFlag.didFire { process.terminate() }
                } catch {
                    // Without this the watchdog stays armed and fires terminate()
                    // on a process that never launched.
                    timeoutItem.cancel()
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(
                        code: -1,
                        message: "Failed to launch: \(error.localizedDescription)"
                    ))
                }
            }
        } onCancel: {
            cancelFlag.set()
            if launchFlag.didFire { process.terminate() }
        }
    }
}

/// Lock-guarded one-way flag, safe to set and read across the dispatch queues
/// that run the watchdog and the termination handler. `nonisolated` because
/// those queues sit outside the MainActor default isolation, and because an
/// implicit isolated deinit would abort when the last release happens off-task.
private nonisolated final class TimeoutFlag: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var fired = false

    nonisolated func set() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    nonisolated var didFire: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}
