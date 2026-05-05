import Foundation

private struct LoudnormStats {
    let inputI: String
    let inputTP: String
    let inputLRA: String
    let inputThresh: String
    let targetOffset: String
}

struct JobInput: Sendable {
    let id: UUID
    let url: URL
}

actor AudioProcessor {
    let settings: ClipHackSettings
    let onFileStarted: (@Sendable (UUID) -> Void)?
    let onFileCompleted: (@Sendable (UUID, URL) -> Void)?

    init(
        settings: ClipHackSettings,
        onFileStarted: (@Sendable (UUID) -> Void)? = nil,
        onFileCompleted: (@Sendable (UUID, URL) -> Void)? = nil
    ) {
        self.settings = settings
        self.onFileStarted = onFileStarted
        self.onFileCompleted = onFileCompleted
    }

    func run(inputs: [JobInput]) async throws -> [JobResult] {
        guard !inputs.isEmpty else { return [] }

        let tools = try await FFmpegManager.shared.ensureTools()
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(1, min(cores, 8))

        return try await withThrowingTaskGroup(of: JobResult.self) { group in
            var results: [JobResult] = []
            var index = 0

            func addNext() {
                guard index < inputs.count else { return }
                let input = inputs[index]
                index += 1
                group.addTask {
                    try Task.checkCancellation()
                    self.onFileStarted?(input.id)
                    let result = try await self.processOne(input.url, id: input.id, tools: tools)
                    self.onFileCompleted?(result.id, result.output)
                    return result
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                addNext()
            }

            for try await result in group {
                results.append(result)
                addNext()
            }

            return results
        }
    }

    private func processOne(_ input: URL, id: UUID, tools: FFmpegManager.Paths) async throws -> JobResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: input.path) else {
            throw ProcessingError.invalidInput
        }

        let sr = settings.sampleRate.rawValue
        let rateTag = sr == 44100 ? "44k" : "48k"
        let stem = input.deletingPathExtension().lastPathComponent
        let limitAmp = pow(10.0, settings.limitDb / 20.0)
        let limitTag = formatDbTag(settings.limitDb)
        let outDir = bestOutputDir(for: input)
        let levelTag = settings.levelingEnabled ? "leveled-" : ""
        let normTag = settings.loudnormEnabled ? "norm-" : ""
        let outName = "\(stem)-\(rateTag)\(levelTag)\(normTag)clipped-\(limitTag).wav"
        let finalURL = outDir.appendingPathComponent(outName)
        let tmpURL = outDir.appendingPathComponent(".\(outName).tmp")

        let work = try makeTemp(prefix: "cliphacker_\(rateTag)_")
        defer { try? fm.removeItem(at: work) }

        // Detect input channel count and sample rate.
        // Fields are output in ffprobe's internal order (sample_rate, channels) regardless
        // of the order specified in show_entries — parsing matches that internal order.
        let probeArgs = [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels",
            "-of", "csv=p=0", input.path
        ]
        let probeOutput = try await runFFmpegCapture(exe: tools.ffprobe, args: probeArgs)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let probeFields = probeOutput.split(separator: ",")
        let inputSampleRate = probeFields.count >= 1 ? Int(probeFields[0]) ?? sr : sr
        let channels = probeFields.count >= 2 ? Int(probeFields[1]) ?? 2 : 2
        let outputChannels = settings.stereoOutput ? max(2, channels) : 1

        // Stage 1: Resample to target sample rate (skip if already matching)
        var currentURL: URL = input
        if inputSampleRate != sr {
            let midURL = work.appendingPathComponent("\(stem)_\(rateTag)24.wav")
            try await runFFmpeg(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", "aresample=\(sr)",
                "-c:a", "pcm_s24le", "-ar", "\(sr)", midURL.path
            ])
            currentURL = midURL
        }

        try Task.checkCancellation()

        // Stage 2: Channel extraction — pan stereo to mono when not in stereo mode
        if !settings.stereoOutput && channels > 1 {
            let chanURL = work.appendingPathComponent("\(stem)_ch.wav")
            let pan = settings.channel == .left ? "pan=1c|c0=c0" : "pan=1c|c0=c1"
            try await runFFmpeg(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", pan,
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "1", chanURL.path
            ])
            currentURL = chanURL
        }

        try Task.checkCancellation()

        // Stage 2.5: High-pass filter + phase rotation (always applied)
        let hpURL = work.appendingPathComponent("\(stem)_hp.wav")
        let hpAf = "highpass=f=\(settings.dcBlockHz),allpass=f=200:t=q:w=0.707"
        try await runFFmpeg(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", currentURL.path, "-af", hpAf,
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", hpURL.path
        ])
        currentURL = hpURL

        try Task.checkCancellation()

        // Stage 3: Leveling (optional)
        // dynaudnorm boundary fix: the Gaussian window extends into nonexistent frames
        // at both the head and the tail, causing fade-in / fade-out artifacts. adelay
        // prepends 16s of silence and apad appends 16s; -ss skips the head padding and
        // -t trims the tail. Both artifacts land in the discarded silence.
        if settings.levelingEnabled {
            let leveledURL = work.appendingPathComponent("\(stem)_leveled.wav")
            let durationOutput = try? await runFFmpegCapture(exe: tools.ffprobe, args: [
                "-v", "error", "-select_streams", "a:0",
                "-show_entries", "format=duration",
                "-of", "csv=p=0", currentURL.path
            ])
            let fileDuration = durationOutput.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                        "-i", currentURL.path,
                        "-af", "adelay=delays=16000:all=1,apad=pad_dur=16,\(levelingFilter())",
                        "-ss", "16"]
            if let d = fileDuration { args += ["-t", String(format: "%.6f", d)] }
            args += ["-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", leveledURL.path]
            try await runFFmpeg(exe: tools.ffmpeg, args: args)
            currentURL = leveledURL
        }

        try Task.checkCancellation()

        // Stage 4: Loudness normalization (optional, two-pass EBU R128)
        if settings.loudnormEnabled {
            let target = settings.loudnormTarget
            let tp = settings.limitDb
            let analyzeAf = "loudnorm=I=\(target):TP=\(tp):LRA=20:print_format=json"
            let analysisOutput = try await runFFmpegCapture(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner",
                "-i", currentURL.path, "-af", analyzeAf,
                "-f", "null", "/dev/null"
            ], captureStderr: true)
            let stats = try parseLoudnormStats(analysisOutput)
            let normAf = "loudnorm=I=\(target):TP=\(tp):LRA=20:measured_I=\(stats.inputI):measured_TP=\(stats.inputTP):measured_LRA=\(stats.inputLRA):measured_thresh=\(stats.inputThresh):offset=\(stats.targetOffset):linear=true"
            let normURL = work.appendingPathComponent("\(stem)_norm.wav")
            try await runFFmpeg(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", normAf,
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", normURL.path
            ])
            currentURL = normURL
        }

        try Task.checkCancellation()

        // Stage 5: Brick-wall limiter with 2x oversampling
        let oversampleSr = sr * 2
        let limiterAf = [
            "aresample=\(oversampleSr)",
            "alimiter=limit=\(limitAmp):attack=5:release=50:level=disabled",
            "aresample=\(sr)"
        ].joined(separator: ",")

        if fm.fileExists(atPath: tmpURL.path) {
            try? fm.removeItem(at: tmpURL)
        }

        try await runFFmpeg(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", currentURL.path, "-af", limiterAf,
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", "-f", "wav", tmpURL.path
        ])

        guard let attrs = try? fm.attributesOfItem(atPath: tmpURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0 else {
            throw ProcessingError.outputMissing
        }

        let resolvedURL = uniqueOutputURL(finalURL, fm: fm)
        try fm.moveItem(at: tmpURL, to: resolvedURL)

        return JobResult(id: id, input: input, output: resolvedURL)
    }

    // MARK: - Process runner

    /// Runs an FFmpeg-compatible process. Captures stdout when `captureStdout` is true,
    /// returns stderr content when `returnStderr` is true. Always reads stderr for error reporting.
    @discardableResult
    private nonisolated func runProcess(
        exe: String,
        args: [String],
        captureStdout: Bool = false,
        returnStderr: Bool = false
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: exe) else {
            throw ProcessingError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice

        // Thread-safe state shared between the cancellation handler (arbitrary thread)
        // and the process termination handler (Process internal thread).
        // stdoutData/stderrData are written by dispatch queues and read only after
        // readGroup.wait(), which provides the required happens-before guarantee.
        final class RunState: @unchecked Sendable {
            private let lock = NSLock()
            private var _cancelled = false
            var cancelled: Bool {
                get { lock.withLock { _cancelled } }
                set { lock.withLock { _cancelled = newValue } }
            }
            var stdoutData = Data()
            var stderrData = Data()
        }
        let state = RunState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = captureStdout ? stdoutPipe : FileHandle.nullDevice
                process.standardError = stderrPipe

                let readGroup = DispatchGroup()

                if captureStdout {
                    readGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        state.stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        readGroup.leave()
                    }
                }
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    state.stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                process.terminationHandler = { proc in
                    readGroup.wait()
                    if proc.terminationReason == .uncaughtSignal || state.cancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let exitCode = proc.terminationStatus
                    if exitCode != 0 {
                        let msg = String(data: state.stderrData, encoding: .utf8) ?? ""
                        continuation.resume(throwing: ProcessingError.ffmpegFailed(
                            code: exitCode,
                            message: msg.isEmpty ? "Exit code \(exitCode)" : msg
                        ))
                        return
                    }
                    if returnStderr {
                        continuation.resume(returning: String(data: state.stderrData, encoding: .utf8) ?? "")
                    } else if captureStdout {
                        continuation.resume(returning: String(data: state.stdoutData, encoding: .utf8) ?? "")
                    } else {
                        continuation.resume(returning: "")
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(
                        code: -1, message: "Failed to launch: \(error.localizedDescription)"
                    ))
                }
            }
        } onCancel: {
            state.cancelled = true
            process.terminate()
        }
    }

    private nonisolated func runFFmpeg(exe: String, args: [String]) async throws {
        try await runProcess(exe: exe, args: args)
    }

    private nonisolated func runFFmpegCapture(exe: String, args: [String], captureStderr: Bool = false) async throws -> String {
        try await runProcess(exe: exe, args: args, captureStdout: !captureStderr, returnStderr: captureStderr)
    }

    // MARK: - Helpers

    /// Returns `url` unchanged if no file exists there, otherwise appends ` (1)`, ` (2)`, … until
    /// a non-colliding path is found. Never overwrites an existing file silently.
    private func uniqueOutputURL(_ url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        let dir  = url.deletingLastPathComponent()
        var counter = 1
        while true {
            let candidate = dir.appendingPathComponent("\(stem) (\(counter)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func makeTemp(prefix: String) throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ProcessingError.tempDirectoryFailed
        }
        return dir
    }

    // Fixed moderate dynaudnorm parameters tuned for broadcast clip conforming.
    // f=450ms, g=19: responsive enough to catch within-clip level swings without pumping.
    // p=0.95: peak target per frame; r=0 = peak-based (not RMS).
    // m=10.0: max gain cap prevents runaway boost on very quiet frames.
    // s=5.0: compress factor limits extreme gain excursions in both directions,
    //        guarding against sections dipping too low in highly variable content.
    // t=0.05: silence threshold (≈ −26 dBFS) passes near-silent frames at unity.
    // n=1: boundary extension holds gain steady at file edges instead of tapering.
    // b=1: channel-coupled — L and R get identical gain, preserving stereo image.
    private func levelingFilter() -> String {
        "dynaudnorm=f=450:g=19:r=0:p=0.95:m=10.0:s=5.0:n=1:b=1:t=0.05"
    }

    private nonisolated func parseLoudnormStats(_ output: String) throws -> LoudnormStats {
        // Find the last '{' (start of the JSON block), then scan forward to its matching '}'
        guard let braceRange = output.range(of: "{", options: .backwards) else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Could not parse loudnorm analysis output")
        }
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
        guard let jsonEnd else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Could not parse loudnorm analysis output")
        }
        let jsonStr = String(output[braceRange.lowerBound...jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Invalid loudnorm JSON output")
        }
        func field(_ key: String) throws -> String {
            guard let value = json[key] as? String else {
                throw ProcessingError.ffmpegFailed(code: -1, message: "Missing loudnorm field: \(key)")
            }
            return value
        }
        return LoudnormStats(
            inputI:      try field("input_i"),
            inputTP:     try field("input_tp"),
            inputLRA:    try field("input_lra"),
            inputThresh: try field("input_thresh"),
            targetOffset: try field("target_offset")
        )
    }

    /// Formats a limiter ceiling value as a filename tag.
    /// The ceiling is always negative (e.g. -1.0 dB), so the sign is implicit
    /// and omitted to avoid double-dashes in the output filename.
    private func formatDbTag(_ db: Double) -> String {
        var s = String(format: "%.2f", abs(db))
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
        }
        return "\(s)dB"
    }

    private func bestOutputDir(for input: URL) -> URL {
        let fm = FileManager.default

        if let customPath = settings.outputDirectoryPath {
            let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
            if fm.isWritableFile(atPath: customURL.path) { return customURL }
        }

        let here = input.deletingLastPathComponent()
        if fm.isWritableFile(atPath: here.path) { return here }

        let music = fm.homeDirectoryForCurrentUser.appendingPathComponent("Music/ClipHack", isDirectory: true)
        if (try? fm.createDirectory(at: music, withIntermediateDirectories: true)) != nil {
            return music
        }

        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
