import Foundation

struct JobInput: Sendable {
    let id: UUID
    let url: URL
}

actor AudioProcessor {
    let settings: ClipHackSettings
    let onFileStarted: (@Sendable (UUID) -> Void)?

    private var reservedOutputPaths: Set<String> = []

    init(
        settings: ClipHackSettings,
        onFileStarted: (@Sendable (UUID) -> Void)? = nil
    ) {
        self.settings = settings
        self.onFileStarted = onFileStarted
    }

    private enum JobOutcome: Sendable {
        case success(JobResult)
        case failure(ClipHackJobFailure)
        case cancelled
    }

    func run(inputs: [JobInput]) async throws -> ClipHackBatchRunResult {
        guard !inputs.isEmpty else {
            return ClipHackBatchRunResult(successes: [], failures: [])
        }

        reservedOutputPaths.removeAll(keepingCapacity: true)

        let tools = try await FFmpegManager.shared.ensureTools()
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(1, min(cores, 8))

        return try await withThrowingTaskGroup(of: JobOutcome.self) { group in
            var successes: [JobResult] = []
            var failures: [ClipHackJobFailure] = []
            var index = 0

            func addNext() {
                guard index < inputs.count else { return }
                let input = inputs[index]
                index += 1
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        self.onFileStarted?(input.id)
                        let result = try await self.processOne(input.url, id: input.id, tools: tools)
                        return .success(result)
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return .failure(ClipHackJobFailure(id: input.id, message: message))
                    }
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                addNext()
            }

            for try await outcome in group {
                switch outcome {
                case .success(let result):
                    successes.append(result)
                case .failure(let failure):
                    failures.append(failure)
                case .cancelled:
                    group.cancelAll()
                    throw CancellationError()
                }
                addNext()
            }

            return ClipHackBatchRunResult(successes: successes, failures: failures)
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
        let limitTag = ClipHackFilename.formatDbTag(settings.limitDb)
        let normTag = settings.loudnormEnabled ? "norm-" : ""
        let outDir = OutputDirectory.clipHackOutputDirectory(for: input, settings: settings)
        let (finalURL, outName) = allocateOutput(
            stem: stem,
            rateTag: rateTag,
            normTag: normTag,
            limitTag: limitTag,
            input: input,
            outDir: outDir
        )
        let tmpURL = outDir.appendingPathComponent(".\(outName).tmp")

        let work = try makeTemp(prefix: "cliphack_\(rateTag)_")
        defer { try? fm.removeItem(at: work) }

        let (inputSampleRate, channels) = try await probeStream(exe: tools.ffprobe, url: input)
        let outputChannels = settings.stereoOutput ? max(2, channels) : 1

        var currentURL: URL = input
        if inputSampleRate != sr {
            let midURL = work.appendingPathComponent("\(stem)_\(rateTag)24.wav")
            try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", "aresample=\(sr)",
                "-c:a", "pcm_s24le", "-ar", "\(sr)", midURL.path
            ])
            currentURL = midURL
        }

        try Task.checkCancellation()

        if !settings.stereoOutput && channels > 1 {
            let chanURL = work.appendingPathComponent("\(stem)_ch.wav")
            let pan = settings.channel == .left ? "pan=1c|c0=c0" : "pan=1c|c0=c1"
            try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", pan,
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "1", chanURL.path
            ])
            currentURL = chanURL
        }

        try Task.checkCancellation()

        let hpURL = work.appendingPathComponent("\(stem)_hp.wav")
        let hpAf = "highpass=f=\(settings.hpfCutoff.rawValue),allpass=f=200:t=q:w=0.707"
        try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", currentURL.path, "-af", hpAf,
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", hpURL.path
        ])
        currentURL = hpURL

        try Task.checkCancellation()

        if settings.dynamicLevelingEnabled {
            let dynLevelURL = work.appendingPathComponent("\(stem)_dynleveled.wav")
            let dynFilter = dynamicLevelingFilter(amount: settings.dynamicLevelingAmount)
            if let duration = try? await getAudioDuration(exe: tools.ffprobe, url: currentURL) {
                let filterComplex = mirrorPaddedFilter(duration: duration, leveler: dynFilter)
                try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
                    "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", currentURL.path,
                    "-filter_complex", filterComplex,
                    "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", dynLevelURL.path
                ])
            } else {
                try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
                    "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", currentURL.path,
                    "-af", dynFilter,
                    "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", dynLevelURL.path
                ])
            }
            currentURL = dynLevelURL
            try Task.checkCancellation()
        }

        if settings.loudnormEnabled {
            let target = settings.loudnormTarget
            let tp = settings.limitDb
            let analyzeAf = "loudnorm=I=\(target):TP=\(tp):LRA=20:print_format=json"
            let analysisOutput = try await FFmpegRunner.capture(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner",
                "-i", currentURL.path, "-af", analyzeAf,
                "-f", "null", "/dev/null"
            ])
            guard let lnDict = FFmpegRunner.parseLoudnormJSON(from: analysisOutput),
                  FFmpegRunner.loudnormMeasurementsAreFinite(lnDict),
                  let inputI = lnDict["input_i"],
                  let inputTP = lnDict["input_tp"],
                  let inputLRA = lnDict["input_lra"],
                  let inputThresh = lnDict["input_thresh"],
                  let targetOffset = lnDict["target_offset"]
            else {
                throw ProcessingError.ffmpegFailed(code: -1, message: "Could not parse loudnorm analysis output")
            }

            let normAf = "loudnorm=I=\(target):TP=\(tp):LRA=20:measured_I=\(inputI):measured_TP=\(inputTP):measured_LRA=\(inputLRA):measured_thresh=\(inputThresh):offset=\(targetOffset):linear=true"
            let normURL = work.appendingPathComponent("\(stem)_norm.wav")
            try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                "-i", currentURL.path, "-af", normAf,
                "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", normURL.path
            ])
            currentURL = normURL
        }

        try Task.checkCancellation()

        let oversampleSr = sr * 2
        let limiterAf = [
            "aresample=\(oversampleSr)",
            "alimiter=limit=\(limitAmp):attack=5:release=50:level=disabled",
            "aresample=\(sr)"
        ].joined(separator: ",")

        if fm.fileExists(atPath: tmpURL.path) {
            try? fm.removeItem(at: tmpURL)
        }

        try await FFmpegRunner.run(exe: tools.ffmpeg, args: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", currentURL.path, "-af", limiterAf,
            "-c:a", "pcm_s24le", "-ar", "\(sr)", "-ac", "\(outputChannels)", "-f", "wav", tmpURL.path
        ])

        guard let attrs = try? fm.attributesOfItem(atPath: tmpURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0 else {
            throw ProcessingError.outputMissing
        }

        let resolvedURL = ClipHackFilename.uniqueOutputURL(finalURL, fm: fm)
        try fm.moveItem(at: tmpURL, to: resolvedURL)

        return JobResult(id: id, input: input, output: resolvedURL)
    }

    private func allocateOutput(
        stem: String,
        rateTag: String,
        normTag: String,
        limitTag: String,
        input: URL,
        outDir: URL
    ) -> (url: URL, name: String) {
        let suffix = "\(rateTag)\(normTag)clipped-\(limitTag).wav"
        let baseName = "\(stem)-\(suffix)"
        let baseURL = outDir.appendingPathComponent(baseName)

        if !reservedOutputPaths.contains(baseURL.path) {
            reservedOutputPaths.insert(baseURL.path)
            return (baseURL, baseName)
        }

        let tag = Self.shortPathTag(for: input.path)
        var name = "\(stem)-\(tag)-\(suffix)"
        var url = outDir.appendingPathComponent(name)
        if reservedOutputPaths.contains(url.path) {
            name = "\(stem)-\(tag)-\(UUID().uuidString.prefix(4))-\(suffix)"
            url = outDir.appendingPathComponent(name)
        }
        reservedOutputPaths.insert(url.path)
        return (url, name)
    }

    private nonisolated static func shortPathTag(for path: String) -> String {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%06x", hash & 0xFFFFFF)
    }

    private nonisolated func probeStream(exe: String, url: URL) async throws -> (sampleRate: Int, channels: Int) {
        let output = try await FFmpegRunner.captureStdout(exe: exe, args: [
            "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels",
            "-of", "csv=p=0", url.path
        ])
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard fields.count >= 2,
              let sampleRate = Int(fields[0]), sampleRate > 0,
              let channels = Int(fields[1]), channels > 0 else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Could not parse stream metadata")
        }
        return (sampleRate, channels)
    }

    private func makeTemp(prefix: String) throws -> URL {
        let dir = FileManager.cliphackTempDirectory
            .appendingPathComponent(prefix + UUID().uuidString.prefix(8), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw ProcessingError.tempDirectoryFailed
        }
        return dir
    }

    private func dynamicLevelingFilter(amount: Double) -> String {
        let f = Int(500.0 - amount * 350.0)
        let gRaw = Int(31.0 - amount * 16.0)
        let g = gRaw % 2 == 0 ? gRaw - 1 : gRaw
        let m = 2.0 + amount * 4.0
        return "dynaudnorm=f=\(f):g=\(g):p=0.95:m=\(String(format: "%.1f", m))"
    }

    private func mirrorPaddedFilter(duration: Double, leveler: String) -> String {
        let padDur = min(16.0, duration)
        let tailStart = max(0.0, duration - padDur)
        let pad = String(format: "%.6f", padDur)
        let tStart = String(format: "%.6f", tailStart)
        let dur = String(format: "%.6f", duration)
        return "[0:a]asplit=3[h][m][t];" +
               "[h]atrim=duration=\(pad),areverse,asetpts=PTS-STARTPTS[head];" +
               "[m]asetpts=PTS-STARTPTS[body];" +
               "[t]atrim=start=\(tStart),areverse,asetpts=PTS-STARTPTS[tail];" +
               "[head][body][tail]concat=n=3:v=0:a=1," +
               "\(leveler),atrim=start=\(pad):duration=\(dur),asetpts=PTS-STARTPTS"
    }

    private nonisolated func getAudioDuration(exe: String, url: URL) async throws -> Double {
        let output = try await FFmpegRunner.captureStdout(exe: exe, args: [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ])
        let str = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = Double(str) else {
            throw ProcessingError.ffmpegFailed(code: -1, message: "Could not parse audio duration")
        }
        return d
    }
}
