import Foundation
import Observation
import SwiftUI

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
    private var processingTask: Task<Void, Never>?

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
        let audioURLs = urls.filter { $0.isFileURL }
        let valid = audioURLs.filter { Self.validExtensions.contains($0.pathExtension.lowercased()) }
        let rejected = audioURLs.count - valid.count

        if rejected > 0 {
            alertTitle = "Notice"
            alertMessage = "\(rejected) file\(rejected == 1 ? "" : "s") skipped — unsupported format. Supported: wav, aif, aiff, mp3, flac, m4a, ogg, opus, caf, wma, aac, mp4, mov."
        }

        let newFiles = valid.map { FileItem(url: $0) }
        files.append(contentsOf: newFiles)

        for file in newFiles {
            analyzeFile(file)
            generateWaveform(file)
        }
    }

    func removeSelected() {
        files.removeAll { selectedFileIDs.contains($0.id) }
        selectedFileIDs.removeAll()
    }

    func removeProcessed() {
        let processedIDs = Set(files.filter { $0.isProcessed }.map { $0.id })
        files.removeAll { processedIDs.contains($0.id) }
        selectedFileIDs.subtract(processedIDs)
    }

    func clearAll() {
        files.removeAll()
        selectedFileIDs.removeAll()
    }

    func removeFiles(at offsets: IndexSet) {
        let deletedIDs = Set(offsets.map { files[$0].id })
        files.remove(atOffsets: offsets)
        selectedFileIDs.subtract(deletedIDs)
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Processing

    func process() {
        // Only process files that are ready or retrying after an error.
        // Exclude files still analyzing, already in-flight, or not yet added to the queue.
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

        isProcessing = true

        let currentSettings = settings
        let inputs = processable.map { JobInput(id: $0.id, url: $0.url) }

        // Snapshot analysis stats so they survive the status transition to .processing
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
                        guard let self else { return }
                        Task { @MainActor [self] in
                            if let index = self.files.firstIndex(where: { $0.id == id }) {
                                self.files[index].status = .processing
                            }
                        }
                    },
                    onFileCompleted: { [weak self] id, outputURL in
                        guard let self else { return }
                        Task { @MainActor [self] in
                            if let index = self.files.firstIndex(where: { $0.id == id }) {
                                self.files[index].status = .processed(outputURL: outputURL)
                            }
                            self.generateOutputWaveform(id: id, url: outputURL)
                            self.analyzeOutputFile(id: id, url: outputURL)
                        }
                    }
                )
                let results = try await processor.run(inputs: inputs)
                await NotificationService.showCompletionNotification(fileCount: results.count)
            } catch is CancellationError {
                // User cancelled — no alert needed
            } catch {
                alertTitle = "Error"
                alertMessage = error.localizedDescription
            }

            isProcessing = false
            processingTask = nil
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
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

    // MARK: - Analysis & waveform

    private func analyzeFile(_ file: FileItem) {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[index].status = .analyzing

        Task {
            if let info = try? await AudioAnalyzer.info(url: file.url),
               let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                files[currentIndex].fileInfo = info
            }

            do {
                let stats = try await AudioAnalyzer.analyze(url: file.url)
                if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].status = .ready(stats)
                }
            } catch {
                if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                    files[currentIndex].status = .error(error.localizedDescription)
                }
            }
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
                // Waveform generation failed silently — not critical
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
                // Output waveform generation failed — non-critical, processed file is unaffected
            }
        }
    }
}
