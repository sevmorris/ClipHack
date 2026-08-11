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

    /// Where a download lands: the user's chosen folder, or the default
    /// ~/Music/ClipHack when no custom folder is set (nil or empty).
    nonisolated static func resolveDownloadDirectory(_ customPath: String?) -> URL {
        guard let customPath, !customPath.isEmpty else { return downloadDirectory }
        return URL(fileURLWithPath: customPath, isDirectory: true)
    }

    /// True when a custom download folder is configured but no longer exists as
    /// a directory (moved, deleted, drive unmounted) — the caller re-prompts.
    /// The default (nil/empty) never reports missing; ~/Music/ClipHack is
    /// created on demand.
    nonisolated static func customDownloadDirectoryMissing(_ customPath: String?) -> Bool {
        guard let customPath, !customPath.isEmpty else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: customPath, isDirectory: &isDir)
        return !(exists && isDir.boolValue)
    }

    /// Creates `url` if needed and confirms it's writable by writing and
    /// removing a probe file — run in the app process so any macOS
    /// Files-and-Folders prompt is attributed to ClipHack, not the yt-dlp child.
    /// Returns false if the folder can't be created or written.
    nonisolated static func prepareWritableDirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil else {
            return false
        }
        let probe = url.appendingPathComponent(".cliphack-write-\(UUID().uuidString)")
        guard (try? Data().write(to: probe)) != nil else { return false }
        try? fm.removeItem(at: probe)
        return true
    }

    /// Marker prefix used with yt-dlp's `--print` so we can pluck the resolved
    /// filepath out of stdout without exposing it to the progress callback.
    static let filepathMarker = "CLIPHACK_OUT|"

    /// Filesystem-safe stem from a user-entered name, or nil when the input
    /// is blank (nil means: keep yt-dlp's default %(title)s naming).
    /// --restrict-filenames does NOT sanitize literal -o template text
    /// (verified against 2026.06.09), so this is ClipHack's job: newlines and
    /// whitespace runs collapse to single spaces, "/" and ":" become "-"
    /// (path separator; Finder renders ":" as "/"), NUL is dropped, leading
    /// dots (hidden files) and trailing dots are trimmed, and the result is
    /// capped at 180 UTF-8 bytes on a character boundary.
    static func sanitizedStem(_ raw: String) -> String? {
        var stem = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")

        while stem.hasPrefix(".") { stem.removeFirst() }
        while stem.hasSuffix(".") { stem.removeLast() }
        stem = stem.trimmingCharacters(in: .whitespaces)

        if stem.utf8.count > 180 {
            var trimmed = ""
            for char in stem {
                if (trimmed + String(char)).utf8.count > 180 { break }
                trimmed.append(char)
            }
            stem = trimmed.trimmingCharacters(in: .whitespaces)
        }

        return stem.isEmpty ? nil : stem
    }

    /// First stem not claimed by `isTaken`: the stem itself, else "stem-2",
    /// "stem-3", … Closes the wrong-content edge where yt-dlp would treat an
    /// existing file with the same target name as "already downloaded".
    static func uniqueStem(_ stem: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(stem) else { return stem }
        var counter = 2
        while isTaken("\(stem)-\(counter)") { counter += 1 }
        return "\(stem)-\(counter)"
    }

    /// A stem is taken when any entry in `directory` starts with "<stem>." —
    /// catching every extension and yt-dlp's in-flight ".part" files — or *is*
    /// the stem, which is the clip folder an earlier download of that name was
    /// filed into. Case-insensitive to match APFS's default.
    private static func stemIsTaken(_ stem: String, in directory: URL) -> Bool {
        let filenames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let lowered = stem.lowercased()
        let prefix = lowered + "."
        return filenames.contains { $0.lowercased() == lowered || $0.lowercased().hasPrefix(prefix) }
    }

    /// Name for a clip folder holding `stem`'s download, uniquified with -2,
    /// -3, … against anything already on disk at that name (a folder from an
    /// earlier download of the same title, or a stray file).
    static func clipFolderName(for stem: String, in directory: URL) -> String {
        uniqueStem(stem) { candidate in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(candidate).path
            )
        }
    }

    /// Files a finished download into its own folder — `Title.m4a` becomes
    /// `Title/Title.m4a` — so the clip's audio, its notes sidecar, and whatever
    /// ClipHack later renders from it stay together. Returns the new path.
    ///
    /// Best-effort by design: if the folder can't be created or the move fails,
    /// the original path comes back unchanged and the download is still usable.
    /// A tidy folder is a nicety; a lost download is not.
    static func fileIntoClipFolder(_ path: String) -> String {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: path)
        let parent = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else { return path }
        // Already filed — e.g. yt-dlp resolved a file sitting in its own folder.
        guard parent.lastPathComponent != stem else { return path }

        let folder = parent.appendingPathComponent(
            clipFolderName(for: stem, in: parent),
            isDirectory: true
        )
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(source.lastPathComponent)
            try fm.moveItem(at: source, to: target)
            return target.path
        } catch {
            // Only ever the empty folder this call just made: clipFolderName
            // picked a name nothing was using.
            if let contents = try? fm.contentsOfDirectory(atPath: folder.path), contents.isEmpty {
                try? fm.removeItem(at: folder)
            }
            return path
        }
    }

    /// Builds the yt-dlp argument list. Kept separate so flags stay easy to audit.
    /// `-f ba/b` prefers a native audio-only stream (no video bytes downloaded);
    /// `-x` strips audio out of combined formats via the bundled ffmpeg. No
    /// --audio-format on purpose: keep the native codec, no re-encode.
    /// --no-quiet is required because --print implies quiet mode, which would
    /// suppress the progress lines and the already-downloaded notice.
    /// `customStem` is a sanitized filesystem stem; "%" is escaped here because
    /// literal template text is yt-dlp template syntax.
    static func buildArguments(
        url: String,
        destination: String,
        ffmpegDirectory: String,
        customStem: String? = nil
    ) -> [String] {
        let template: String
        if let customStem {
            template = customStem.replacingOccurrences(of: "%", with: "%%") + ".%(ext)s"
        } else {
            template = "%(title)s.%(ext)s"
        }
        return [
            "-f", "ba/b",
            "-x",
            "--ffmpeg-location", ffmpegDirectory,
            "-P", destination,
            "-o", template,
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
    nonisolated static func alreadyDownloadedPath(fromLine line: String) -> String? {
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
    /// `customStem` (already sanitized) names the output file; it is uniquified
    /// against the download directory so a colliding name can never make yt-dlp
    /// skip the download and resolve someone else's file.
    /// Returns the absolute path of the downloaded (or already-present) file,
    /// after filing it into its own clip folder.
    func downloadAudio(
        url: String,
        destination: URL,
        customStem: String? = nil,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let binary = try await YtDlpManager.shared.ensureTool()
        let ffmpegDir = try await YtDlpManager.shared.ffmpegDirectory()

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let uniqueCustomStem = customStem.map { stem in
            Self.uniqueStem(stem) { Self.stemIsTaken($0, in: destination) }
        }

        let marker = Self.filepathMarker
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildArguments(
            url: url,
            destination: destination.path,
            ffmpegDirectory: ffmpegDir,
            customStem: uniqueCustomStem
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
        return Self.fileIntoClipFolder(filepath)
    }
}

nonisolated private func forEachLine(in data: Data, _ body: (String) -> Void) {
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
