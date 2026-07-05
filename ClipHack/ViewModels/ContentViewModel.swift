import AppKit
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
        self.clipListEnabled = UserDefaults.standard.bool(forKey: Self.clipListKey)
    }

    // nonisolated: with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor the implicit
    // deinit would be MainActor-isolated, and macOS 15's isolated-deinit runtime
    // (swift_task_deinitOnExecutor, reached via the back-deploy shim) malloc-aborts
    // tearing down its task-local scope when the last release happens outside a
    // task — e.g. a window's @State view model being discarded, or unit tests.
    // Nothing in teardown needs the actor, so opt out. Covered by deallocation in
    // ContentViewModelDownloadTests.
    nonisolated deinit {}

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

    // MARK: - Rename

    enum RenameOutcome: Equatable {
        case renamed
        case invalidName
        case nameTaken
        case notRenamable
        case renameFailed(String)
    }

    /// Row currently being renamed; non-nil drives the rename alert.
    var renameTargetID: UUID?
    var renameField: String = ""

    /// Analysis and processing capture the file path when they start, so a
    /// rename mid-flight would pull the file out from under ffmpeg/ffprobe.
    func isRenamable(_ file: FileItem) -> Bool {
        switch file.status {
        case .analyzing, .processing: return false
        default: return true
        }
    }

    func beginRename(_ id: UUID) {
        guard let file = files.first(where: { $0.id == id }), isRenamable(file) else { return }
        renameField = file.url.deletingPathExtension().lastPathComponent
        renameTargetID = id
    }

    func cancelRename() {
        renameTargetID = nil
        renameField = ""
    }

    /// Confirms the pending rename; failures surface through the standard
    /// notice alert (re-invoke rename to retry).
    func confirmRename() {
        guard let id = renameTargetID else { return }
        let outcome = renameFile(id: id, to: renameField)
        renameTargetID = nil
        renameField = ""

        let failure: String?
        switch outcome {
        case .renamed, .notRenamable:
            failure = nil
        case .invalidName:
            failure = "Enter a usable file name."
        case .nameTaken:
            failure = "A file with that name already exists in the same folder."
        case .renameFailed(let message):
            failure = message
        }
        if let failure {
            alertTitle = "Rename Failed"
            alertMessage = failure
        }
    }

    /// Renames the file on disk (stem only, extension preserved) and updates
    /// the row's URL. Computed row state (waveform, stats, notes) is untouched.
    func renameFile(id: UUID, to rawName: String) -> RenameOutcome {
        guard let index = files.firstIndex(where: { $0.id == id }),
              isRenamable(files[index]) else { return .notRenamable }
        guard let stem = YtDlpService.sanitizedStem(rawName) else { return .invalidName }

        let sourceURL = files[index].url
        var destURL = sourceURL.deletingLastPathComponent().appendingPathComponent(stem)
        let ext = sourceURL.pathExtension
        if !ext.isEmpty {
            destURL = destURL.appendingPathExtension(ext)
        }

        if destURL.path == sourceURL.path { return .renamed }

        // APFS is case-insensitive by default, so an exists-check for a
        // case-only change would match the source file itself — allow it.
        let isCaseOnlyChange = destURL.path.lowercased() == sourceURL.path.lowercased()
        if !isCaseOnlyChange, FileManager.default.fileExists(atPath: destURL.path) {
            return .nameTaken
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        } catch {
            return .renameFailed(error.localizedDescription)
        }

        files[index].url = destURL
        return .renamed
    }

    // MARK: - Download from URL

    /// Single source of truth for the download UI — the popover's status line
    /// and its Download/Cancel button switch on this directly.
    enum DownloadState: Equatable {
        case idle
        case downloading(progress: String)
        case failed(String)
    }

    var downloadURLField: String = ""
    /// Optional custom filename (stem only); blank keeps the source title.
    var downloadNameField: String = ""
    /// Optional free-text carried onto the added row and into the clip list.
    var downloadNotesField: String = ""
    /// "Save clip list": append an entry to the daily clip-list file next to
    /// each successful download. Persisted across launches.
    var clipListEnabled: Bool {
        didSet { UserDefaults.standard.set(clipListEnabled, forKey: Self.clipListKey) }
    }
    private static let clipListKey = "clipListEnabled"
    var isDownloadPopoverPresented = false
    var downloadState: DownloadState = .idle

    var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    private var downloadTask: Task<Void, Never>?
    /// Source URL → file-browser row added for it, for session-scoped dedupe.
    private var downloadedURLToFileID: [String: UUID] = [:]

    /// Trimmed http(s) URL, or nil if the string isn't a usable web URL.
    static func validatedWebURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return trimmed
    }

    /// A URL dropped onto the window: prefill the popover and open it. Never
    /// starts the download — that takes an explicit click on Download.
    @discardableResult
    func acceptDroppedURL(_ raw: String) -> Bool {
        guard let url = Self.validatedWebURL(raw) else { return false }
        downloadURLField = url
        if case .failed = downloadState {
            downloadState = .idle
        }
        isDownloadPopoverPresented = true
        return true
    }

    /// Convenience when the popover opens: prefill an empty URL field from the
    /// pasteboard if it holds a plausible web URL. Never starts the download.
    func prefillDownloadFromPasteboard() {
        guard downloadURLField.isEmpty,
              let pasted = NSPasteboard.general.string(forType: .string),
              let url = Self.validatedWebURL(pasted) else { return }
        downloadURLField = url
    }

    /// The row previously added for `sourceURL`, if it is still in the list.
    func existingDownloadRowID(for sourceURL: String) -> UUID? {
        guard let id = downloadedURLToFileID[sourceURL],
              files.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func startDownload() {
        guard !isDownloading else { return }
        guard let url = Self.validatedWebURL(downloadURLField) else {
            downloadState = .failed("Enter a valid http(s) URL.")
            return
        }

        if let existingID = existingDownloadRowID(for: url) {
            selectedFileIDs = [existingID]
            downloadURLField = ""
            downloadNameField = ""
            downloadNotesField = ""
            downloadState = .idle
            isDownloadPopoverPresented = false
            return
        }

        let stem = YtDlpService.sanitizedStem(downloadNameField)
        downloadState = .downloading(progress: "Starting download…")

        downloadTask = Task {
            defer { downloadTask = nil }
            do {
                let path = try await YtDlpService.shared.downloadAudio(url: url, customStem: stem) { [weak self] line in
                    Task { @MainActor in
                        // Stale lines can trail a finished/failed download —
                        // never let one overwrite a terminal state.
                        guard let self, self.isDownloading else { return }
                        self.downloadState = .downloading(progress: line)
                    }
                }
                finishDownload(sourceURL: url, filePath: path)
            } catch is CancellationError {
                downloadState = .idle
            } catch YtDlpError.cancelled {
                downloadState = .idle
            } catch {
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Feeds a completed download through the existing add-files path, then
    /// records and selects the row that landed, attaches notes, and appends
    /// to the clip list when enabled. Internal for unit tests.
    func finishDownload(sourceURL: String, filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        let countBefore = files.count
        addFiles([fileURL])
        // addFiles can reject (unsupported extension) or defer to the
        // reprocess warning — only record and select a row that landed.
        guard files.count > countBefore,
              let index = files.lastIndex(where: { $0.url == fileURL }) else {
            downloadState = .idle
            return
        }

        let notes = downloadNotesField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            files[index].notes = notes
        }

        if clipListEnabled {
            do {
                try ClipListManifest.append(
                    entry: ClipListManifest.entry(
                        filename: fileURL.lastPathComponent,
                        notes: notes,
                        sourceURL: sourceURL
                    ),
                    in: fileURL.deletingLastPathComponent()
                )
            } catch {
                alertTitle = "Notice"
                alertMessage = "Downloaded, but the clip list could not be written: \(error.localizedDescription)"
            }
        }

        downloadedURLToFileID[sourceURL] = files[index].id
        selectedFileIDs = [files[index].id]
        downloadState = .idle
        downloadURLField = ""
        downloadNameField = ""
        downloadNotesField = ""
        isDownloadPopoverPresented = false
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
