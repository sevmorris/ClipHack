import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClipHack", category: "waveform")

@Observable
@MainActor
final class ContentViewModel {
    var files: [FileItem] = []
    var selectedFileIDs: Set<UUID> = []
    var settings: ClipHackSettings {
        didSet { settings.save() }
    }
    var presetStore = ClipHackPresetStore()
    var isProcessing = false
    var alertMessage: String?
    var alertTitle: String = "Error"
    var showReprocessWarning = false
    private var pendingReprocessFiles: [URL] = []
    private var processingTask: Task<Void, Never>?
    private var processingCancelled = false
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    private static let validExtensions: Set<String> = [
        "wav", "aif", "aiff", "mp3", "flac", "m4a", "ogg", "opus", "caf", "wma", "aac",
        "mp4", "mov"
    ]

    init() {
        self.settings = ClipHackSettings.load()
    }

    // MARK: - Computed

    /// True when at least one file is ready to process.
    var hasProcessableFiles: Bool {
        files.contains {
            switch $0.status {
            case .ready, .error: return true
            default: return false
            }
        }
    }

    /// True when any file is currently being analyzed (analysis runs async after adding).
    var isAnyFileAnalyzing: Bool {
        files.contains { if case .analyzing = $0.status { return true }; return false }
    }

    // MARK: - Presets

    func applyPreset(_ preset: ClipHackPreset) {
        let savedOutputDir = settings.outputDirectoryPath
        settings = preset.settings
        settings.outputDirectoryPath = savedOutputDir
        presetStore.selectedPresetID = preset.id
    }

    func saveCurrentAsPreset(name: String) {
        presetStore.savePreset(name: name, settings: settings)
    }

    // MARK: - File management

    func addFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        let valid = fileURLs.filter { Self.validExtensions.contains($0.pathExtension.lowercased()) }
        let folders = urls.filter { $0.hasDirectoryPath }.count
        let badFormat = fileURLs.count - valid.count

        var notices: [String] = []
        if folders > 0 {
            notices.append("\(folders) folder\(folders == 1 ? "" : "s") skipped — folders are not supported.")
        }
        if badFormat > 0 {
            notices.append("\(badFormat) file\(badFormat == 1 ? "" : "s") skipped — unsupported format. Supported: wav, aif, aiff, mp3, flac, m4a, ogg, opus, caf, wma, aac, mp4, mov.")
        }
        if !notices.isEmpty {
            alertTitle = "Notice"
            alertMessage = notices.joined(separator: "\n\n")
        }

        if valid.contains(where: ClipHackOutputNaming.looksLikeClipHackOutput) {
            pendingReprocessFiles = valid
            showReprocessWarning = true
            return
        }

        commitFiles(valid)
    }

    func confirmReprocessWarning() {
        let toAdd = pendingReprocessFiles
        pendingReprocessFiles = []
        showReprocessWarning = false
        commitFiles(toAdd)
    }

    func dismissReprocessWarning() {
        pendingReprocessFiles = []
        showReprocessWarning = false
    }

    private func commitFiles(_ urls: [URL]) {
        let newFiles = urls.map { FileItem(url: $0) }
        files.append(contentsOf: newFiles)

        for file in newFiles {
            analyzeFile(file)
            generateWaveform(file)
        }
    }

    func removeSelected() {
        cancelAnalysisTasks(for: selectedFileIDs)
        files.removeAll { selectedFileIDs.contains($0.id) }
        selectedFileIDs.removeAll()
    }

    func removeProcessed() {
        let processedIDs = Set(files.filter { $0.isProcessed }.map { $0.id })
        cancelAnalysisTasks(for: processedIDs)
        files.removeAll { processedIDs.contains($0.id) }
        selectedFileIDs.subtract(processedIDs)
    }

    func clearAll() {
        cancelAnalysisTasks(for: Set(files.map { $0.id }))
        files.removeAll()
        selectedFileIDs.removeAll()
    }

    func removeFiles(at offsets: IndexSet) {
        let deletedIDs = Set(offsets.map { files[$0].id })
        cancelAnalysisTasks(for: deletedIDs)
        files.remove(atOffsets: offsets)
        selectedFileIDs.subtract(deletedIDs)
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Processing

    func process() {
        let processable = files.filter {
            switch $0.status {
            case .ready, .error: return true
            default: return false
            }
        }
        guard !processable.isEmpty else { return }

        if let customPath = settings.outputDirectoryPath,
           !FileManager.default.isWritableFile(atPath: customPath) {
            alertTitle = "Error"
            alertMessage = "Output directory is not writable: \(customPath)"
            return
        }

        let inputs = processable.map { JobInput(id: $0.id, url: $0.url) }
        var outputWarnings: [String] = []
        let outputDirectories = inputs.map { input in
            OutputDirectory.clipHackOutputDirectory(for: input.url, settings: settings) { warning in
                if !outputWarnings.contains(warning) {
                    outputWarnings.append(warning)
                }
            }
        }
        if !outputWarnings.isEmpty {
            alertTitle = "Notice"
            alertMessage = outputWarnings.joined(separator: "\n\n")
        }
        let concurrentJobs = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        if let reason = DiskSpaceChecker.clipHackBatchBlockedReason(
            inputURLs: inputs.map(\.url),
            outputDirectories: outputDirectories,
            concurrentJobs: concurrentJobs
        ) {
            alertTitle = "Error"
            alertMessage = reason
            return
        }

        isProcessing = true
        processingCancelled = false

        let currentSettings = settings

        for i in files.indices {
            if case .ready(let stats) = files[i].status {
                files[i].analysisStats = stats
            }
        }

        processingTask = Task {
            do {
                let processor = AudioProcessor(
                    settings: currentSettings,
                    onFileStarted: { [weak self] id in
                        Task { @MainActor [weak self] in
                            guard let self, !self.processingCancelled else { return }
                            if let index = self.files.firstIndex(where: { $0.id == id }) {
                                self.files[index].status = .processing
                            }
                        }
                    }
                )
                let batch = try await processor.run(inputs: inputs)

                for result in batch.successes {
                    if let index = files.firstIndex(where: { $0.id == result.id }) {
                        files[index].status = .processed(outputURL: result.output)
                    }
                }

                for failure in batch.failures {
                    if let index = files.firstIndex(where: { $0.id == failure.id }) {
                        files[index].status = .error(failure.message)
                    }
                }

                resetStuckProcessingRows()

                for result in batch.successes {
                    generateOutputWaveform(id: result.id, url: result.output)
                    analyzeOutputFile(id: result.id, url: result.output)
                }

                if batch.failures.isEmpty {
                    await NotificationService.showCompletionNotification(fileCount: batch.successes.count)
                } else if batch.successes.isEmpty {
                    alertTitle = "Error"
                    alertMessage = "Processing failed for all files."
                } else {
                    alertTitle = "Notice"
                    alertMessage = "\(batch.successes.count) file\(batch.successes.count == 1 ? "" : "s") processed, \(batch.failures.count) failed."
                    await NotificationService.showCompletionNotification(fileCount: batch.successes.count)
                }
            } catch is CancellationError {
                resetStuckProcessingRows()
            } catch {
                alertTitle = "Error"
                alertMessage = error.localizedDescription
                resetStuckProcessingRows()
            }

            isProcessing = false
            processingTask = nil
        }
    }

    func cancelProcessing() {
        processingCancelled = true
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        for i in files.indices {
            if case .processing = files[i].status {
                if let stats = files[i].analysisStats {
                    files[i].status = .ready(stats)
                } else {
                    files[i].status = .pending
                }
            }
        }
    }

    private func resetStuckProcessingRows() {
        for i in files.indices {
            guard case .processing = files[i].status else { continue }
            if let stats = files[i].analysisStats {
                files[i].status = .ready(stats)
            } else {
                files[i].status = .error("Processing interrupted")
            }
        }
    }

    // MARK: - Analysis & waveform

    private func analyzeFile(_ file: FileItem) {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[index].status = .analyzing

        let task = Task {
            do {
                let tools = try await FFmpegManager.shared.ensureTools()
                guard await AudioStreamProbe.hasAudioStream(ffprobe: tools.ffprobe, url: file.url) else {
                    if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                        files[currentIndex].status = .error("No audio stream found — file may be misnamed or unsupported.")
                    }
                    analysisTasks.removeValue(forKey: file.id)
                    return
                }

                if let info = try? await AudioAnalyzer.info(url: file.url),
                   let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].fileInfo = info
                }

                let stats = try await AudioAnalyzer.analyze(url: file.url)
                if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].status = .ready(stats)
                }
            } catch {
                if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].status = .error(error.localizedDescription)
                }
            }
            analysisTasks.removeValue(forKey: file.id)
        }
        analysisTasks[file.id] = task
    }

    private func cancelAnalysisTasks(for ids: Set<UUID>) {
        for id in ids {
            analysisTasks[id]?.cancel()
            analysisTasks.removeValue(forKey: id)
        }
    }

    private func generateWaveform(_ file: FileItem) {
        Task {
            do {
                let waveform = try await WaveformGenerator.generate(url: file.url)
                if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].waveform = waveform
                }
            } catch {
                logger.warning("Input waveform generation failed for '\(file.url.lastPathComponent, privacy: .public)': \(error)")
            }
        }
    }

    private func analyzeOutputFile(id: UUID, url: URL) {
        Task {
            if let info = try? await AudioAnalyzer.info(url: url),
               let index = files.firstIndex(where: { $0.id == id }) {
                files[index].outputFileInfo = info
            }
            if let stats = try? await AudioAnalyzer.analyze(url: url),
               let index = files.firstIndex(where: { $0.id == id }) {
                files[index].outputStats = stats
            }
        }
    }

    private func generateOutputWaveform(id: UUID, url: URL) {
        Task {
            do {
                let waveform = try await WaveformGenerator.generate(url: url)
                if let currentIndex = files.firstIndex(where: { $0.id == id }) {
                    files[currentIndex].outputWaveform = waveform
                }
            } catch {
                logger.warning("Output waveform generation failed for '\(url.lastPathComponent, privacy: .public)': \(error)")
            }
        }
    }
}
