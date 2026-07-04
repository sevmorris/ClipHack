@preconcurrency import Foundation

enum YtDlpError: LocalizedError {
    case notFound
    case executionFailed(String)
    case cancelled
    case noOutputFile

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "The bundled downloader (yt-dlp) is missing. Try reinstalling ClipHack."
        case .executionFailed(let message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download cancelled"
        case .noOutputFile:
            return "Download finished but no output file was found."
        }
    }
}

final class YtDlpService {
    static let shared = YtDlpService()

    private init() {}

    /// Downloads land here, created on demand. ~/Music is not TCC-protected
    /// (no permission prompt) and is already ClipHack's fallback output home.
    nonisolated static var downloadDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/ClipHack", isDirectory: true)
    }

    /// Marker prefix used with yt-dlp's `--print` so we can pluck the resolved
    /// filepath out of stdout without exposing it to the progress callback.
    static let filepathMarker = "CLIPHACK_OUT|"

    /// Builds the yt-dlp argument list. Kept separate so flags stay easy to audit.
    /// `-f ba/b` prefers a native audio-only stream (no video bytes downloaded);
    /// `-x` strips audio out of combined formats via the bundled ffmpeg. No
    /// --audio-format on purpose: keep the native codec, no re-encode.
    /// --no-quiet is required because --print implies quiet mode, which would
    /// suppress the progress lines and the already-downloaded notice.
    static func buildArguments(
        url: String,
        destination: String,
        ffmpegDirectory: String
    ) -> [String] {
        [
            "-f", "ba/b",
            "-x",
            "--ffmpeg-location", ffmpegDirectory,
            "-P", destination,
            "-o", "%(title)s.%(ext)s",
            "--print", "after_move:\(filepathMarker)%(filepath)s",
            "--no-quiet",
            "--no-playlist",
            "--newline",
            "--restrict-filenames",
            "--retries", "10",
            "--fragment-retries", "10",
            "-N", "4",
            "--remote-components", "ejs:github",
            url,
        ]
    }

    /// Parses yt-dlp's "[download] <path> has already been downloaded" notice —
    /// emitted instead of the after_move print when the target file already
    /// exists on disk and the download is skipped.
    static func alreadyDownloadedPath(fromLine line: String) -> String? {
        let prefix = "[download] "
        let suffix = " has already been downloaded"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix),
              line.count > prefix.count + suffix.count else { return nil }
        return String(line.dropFirst(prefix.count).dropLast(suffix.count))
    }

    /// Picks the final downloaded file. The after_move marker is authoritative;
    /// when absent (already-downloaded skip), fall back to the path from the
    /// skip notice, resolved against the destination directory and verified on
    /// disk. Returns nil only when no usable file can be located.
    static func resolveDownloadedFile(
        markerPath: String?,
        alreadyDownloadedPath: String?,
        destination: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        if let markerPath, !markerPath.isEmpty {
            return markerPath
        }
        guard let alreadyDownloadedPath, !alreadyDownloadedPath.isEmpty else { return nil }
        let resolved: String
        if alreadyDownloadedPath.hasPrefix("/") {
            resolved = alreadyDownloadedPath
        } else {
            resolved = URL(fileURLWithPath: destination, isDirectory: true)
                .appendingPathComponent(alreadyDownloadedPath).path
        }
        return fileExists(resolved) ? resolved : nil
    }

    /// Streams yt-dlp output line-by-line via `onProgress`. Cancels by terminating
    /// the child process when the surrounding `Task` is cancelled.
    /// Returns the absolute path of the downloaded (or already-present) file.
    func downloadAudio(
        url: String,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let binary = try await YtDlpManager.shared.ensureTool()
        let ffmpegDir = try await YtDlpManager.shared.ffmpegDirectory()

        let destination = Self.downloadDirectory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let marker = Self.filepathMarker
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildArguments(
            url: url,
            destination: destination.path,
            ffmpegDirectory: ffmpegDir
        )
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Tail recent stderr for the failure message — yt-dlp's actionable error
        // is usually within the last few hundred bytes.
        let stderrTail = StderrTail()
        let filepathCapture = FilepathCapture()
        let alreadyDownloadedCapture = FilepathCapture()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Drain both pipes concurrently. Reading only one to EOF before the
        // other deadlocks the child once its sibling pipe buffer fills.
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            forEachLine(in: data) { line in
                if line.hasPrefix(marker) {
                    filepathCapture.set(String(line.dropFirst(marker.count)))
                } else {
                    if let existing = Self.alreadyDownloadedPath(fromLine: line) {
                        alreadyDownloadedCapture.set(existing)
                    }
                    onProgress(line)
                }
            }
        }
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrTail.append(data)
            forEachLine(in: data) { onProgress($0) }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { proc in
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    if proc.terminationReason == .uncaughtSignal {
                        cont.resume(throwing: YtDlpError.cancelled)
                    } else if proc.terminationStatus == 0 {
                        cont.resume(returning: ())
                    } else {
                        let tail = stderrTail.snapshot().trimmingCharacters(in: .whitespacesAndNewlines)
                        let msg = tail.isEmpty
                            ? "yt-dlp exited with code \(proc.terminationStatus)"
                            : tail
                        cont.resume(throwing: YtDlpError.executionFailed(msg))
                    }
                }

                do {
                    try process.run()
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        guard let filepath = Self.resolveDownloadedFile(
            markerPath: filepathCapture.get(),
            alreadyDownloadedPath: alreadyDownloadedCapture.get(),
            destination: destination.path
        ) else {
            throw YtDlpError.noOutputFile
        }
        return filepath
    }
}

private func forEachLine(in data: Data, _ body: (String) -> Void) {
    guard let chunk = String(data: data, encoding: .utf8) else { return }
    // yt-dlp progress can use either \n (with --newline) or \r. Split on both.
    for raw in chunk.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let line = String(raw).trimmingCharacters(in: .whitespaces)
        if !line.isEmpty { body(line) }
    }
}

// nonisolated: these boxes synchronize with their own lock and are touched from
// pipe-handler threads, so the project's MainActor default isolation is wrong for
// them — and the implicit MainActor deinit it would add malloc-aborts in macOS 15's
// isolated-deinit runtime when the last release happens off-task (see
// ContentViewModel.deinit).
private nonisolated final class FilepathCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    func set(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        path = value
    }

    func get() -> String? {
        lock.lock(); defer { lock.unlock() }
        return path
    }
}

private nonisolated final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let cap = 8 * 1024

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        if buffer.count > cap {
            buffer.removeFirst(buffer.count - cap)
        }
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}
