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
    let settings: ClipHackerSettings
    let onFileStarted: (@Sendable (UUID) -> Void)?

    init(settings: ClipHackerSettings, onFileStarted: (@Sendable (UUID) -> Void)? = nil) {
        self.settings = settings
        self.onFileStarted = onFileStarted
    }

    func run(inputs: [JobInput]) async throws -> [JobResult] {
        guard !inputs.isEmpty else { return [] }

        let tools = try await FFmpegManager.shared.ensureTools()
        let maxConcurrent = 3

        return try await withThrowingTaskGroup(of: JobResult?.self) { group in
            var results: [JobResult] = []
            var index = 0

            func addNext() {
                guard index < inputs.count else { return }
                let input = inputs[index]
                index += 1
                group.addTask {
                    try Task.checkCancellation()
                    self.onFileStarted?(input.id)
                    return try await self.processOne(input.url, id: input.id, tools: tools)
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                addNext()
            }

            for try await result in group {
                if let result {
                    results.append(result)
                }
                addNext()
            }

            return results
        }
    }

    private func processOne(_ input: URL, id: UUID, tools: FFmpegManager.Paths) async throws -> JobResult? {
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
        let nrTag = settings.noiseReductionEnabled ? "nr-" : ""
        let levelTag = settings.levelingEnabled ? "leveled-" : ""
        let normTag = settings.loudnormEnabled ? "norm-" : ""
        let outName = "\(stem)-\(rateTag)\(nrTag)\(levelTag)\(normTag)clipped-\(limitTag).wav"
        let finalURL = outDir.appendingPathComponent(outName)
        let tmpURL = outDir.appendingPathComponent(".\(outName).tmp")

        let work = try makeTemp(prefix: "cliphacker_\(rateTag)_")
        defer { try? fm.removeItem(at: work) }

        // Detect input channel count and sample rate
        let probeArgs = [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=channels,sample_rate",
            "-of", "csv=p=0", input.path
        ]
        let probeOutput = try await runFFmpegCapture(exe: tools.ffprobe, args: probeArgs).trimmingCharacters(in: .whitespacesAndNewlines)
        let probeFields = probeOutput.split(separator: ",")
        let inputSampleRate = probeFields.count >= 2 ? Int(probeFields[0]) ?? sr : sr
        let channels = probeFields.count >= 2 ? Int(probeFields[1]) ?? 2 : 2
        let outputChannels = settings.stereoOutput ? max(2, channels) : channels

        // Stage 1: Resample to target sample rate (skip if already matching)
        var currentURL: URL
        if inputSampleRate != sr {
            let midURL = work.appendingPathComponent("\(stem)_\(rateTag)24.wav")
            try await runFFmpeg(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", input.path, "-af", "aresample=\(sr)",
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", midURL.path
            ])
            currentURL = midURL
        } else {
            currentURL = input
        }

        try Task.checkCancellation()

        // Stage 1.5: Noise reduction (optional)
        if settings.noiseReductionEnabled,
           let modelURL = Bundle.main.url(forResource: "rnnoise", withExtension: nil) {
            let nrURL = work.appendingPathComponent("\(stem)_nr.wav")
            if channels > 1 {
                let fc = [
                    "[0:a]channelsplit=channel_layout=stereo[L][R]",
                    "[L]arnndn=m=\(modelURL.path)[Lnr]",
                    "[R]arnndn=m=\(modelURL.path)[Rnr]",
                    "[Lnr][Rnr]join=inputs=2:channel_layout=stereo"
                ].joined(separator: ";")
                try await runFFmpeg(exe: tools.ffmpeg, args: [
                    "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", currentURL.path, "-filter_complex", fc,
                    "-c:a", "pcm_s24le", "-ar", "\(sr)", nrURL.path
                ])
            } else {
                try await runFFmpeg(exe: tools.ffmpeg, args: [
                    "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", currentURL.path, "-af", "arnndn=m=\(modelURL.path)",
                    "-c:a", "pcm_s24le", "-ar", "\(sr)", nrURL.path
                ])
            }
            currentURL = nrURL
        }

        try Task.checkCancellation()

        // Stage 2: Leveling (optional)
        if settings.levelingEnabled {
            let leveledURL = work.appendingPathComponent("\(stem)_leveled.wav")
            try await runFFmpeg(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", levelingFilter(amount: settings.levelingAmount),
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", leveledURL.path
            ])
            currentURL = leveledURL
        }

        try Task.checkCancellation()

        // Stage 3: Loudness normalization (optional, two-pass EBU R128)
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

        // Stage 4: Brick-wall limiter with 2x oversampling
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

        if fm.fileExists(atPath: finalURL.path) {
            try? fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: tmpURL, to: finalURL)

        return JobResult(id: id, input: input, output: finalURL)
    }

    private nonisolated func runFFmpeg(exe: String, args: [String]) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: exe) else {
            throw ProcessingError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        // Box avoids a shared `var` across two closures, satisfying Swift 6 concurrency.
        // readGroup.wait() in the terminationHandler ensures the write always precedes the read.
        final class DataBox: @unchecked Sendable { var value = Data() }
        let box = DataBox()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let readGroup = DispatchGroup()
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    box.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                process.terminationHandler = { proc in
                    readGroup.wait()
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let exitCode = proc.terminationStatus
                    let msg = String(data: box.value, encoding: .utf8) ?? ""
                    if exitCode != 0 {
                        continuation.resume(throwing: ProcessingError.ffmpegFailed(code: exitCode, message: msg.isEmpty ? "Exit code \(exitCode)" : msg))
                    } else {
                        continuation.resume(returning: ())
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(code: -1, message: "Failed to launch: \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    private nonisolated func runFFmpegCapture(exe: String, args: [String], captureStderr: Bool = false) async throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: exe) else {
            throw ProcessingError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class DataBox: @unchecked Sendable { var value = Data() }
        let stdoutBox = DataBox()
        let stderrBox = DataBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let readGroup = DispatchGroup()

                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stdoutBox.value = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrBox.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                process.terminationHandler = { proc in
                    readGroup.wait()
                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let exitCode = proc.terminationStatus
                    if exitCode != 0 {
                        let msg = String(data: stderrBox.value, encoding: .utf8) ?? ""
                        continuation.resume(throwing: ProcessingError.ffmpegFailed(code: exitCode, message: msg.isEmpty ? "Exit code \(exitCode)" : msg))
                    } else {
                        let output = captureStderr
                            ? (String(data: stderrBox.value, encoding: .utf8) ?? "")
                            : (String(data: stdoutBox.value, encoding: .utf8) ?? "")
                        continuation.resume(returning: output)
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessingError.ffmpegFailed(code: -1, message: "Failed to launch: \(error.localizedDescription)"))
                }
            }
        } onCancel: {
            process.terminate()
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

    // Maps 0.0 (gentle) → 1.0 (aggressive) to dynaudnorm parameters.
    // Shorter frames and tighter Gaussian smoothing = more responsive leveling.
    private func levelingFilter(amount: Double) -> String {
        let f = Int(750.0 - amount * 600.0)         // frame ms: 750 → 150
        let gRaw = Int(31.0 - amount * 24.0)        // gaussian: 31 → 7
        let g = gRaw % 2 == 0 ? gRaw - 1 : gRaw    // must be odd
        let m = 8.0 + amount * 12.0                 // max gain factor: 8x → 20x
        return "dynaudnorm=f=\(f):g=\(g):r=1:p=0.95:m=\(String(format: "%.1f", m)):n=1:b=1"
    }

    private nonisolated func parseLoudnormStats(_ output: String) throws -> LoudnormStats {
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
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: String] else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Invalid loudnorm JSON output")
        }
        guard let inputI = dict["input_i"],
              let inputTP = dict["input_tp"],
              let inputLRA = dict["input_lra"],
              let inputThresh = dict["input_thresh"],
              let targetOffset = dict["target_offset"] else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Missing loudnorm measurement fields")
        }
        return LoudnormStats(
            inputI: inputI, inputTP: inputTP,
            inputLRA: inputLRA, inputThresh: inputThresh,
            targetOffset: targetOffset
        )
    }

    private func formatDbTag(_ db: Double) -> String {
        var s = String(format: "%.2f", db)
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

        let music = fm.homeDirectoryForCurrentUser.appendingPathComponent("Music/ClipHacker", isDirectory: true)
        if (try? fm.createDirectory(at: music, withIntermediateDirectories: true)) != nil {
            return music
        }

        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}
