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
        // Defaults to on, so `bool(forKey:)`'s false-when-absent is wrong here.
        self.trashOriginalsEnabled =
            ClipHackSettings.store.object(forKey: Self.trashOriginalsKey) as? Bool ?? true
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
        // A preset carries a whole ClipHackSettings, so applying one would
        // otherwise move every folder the user has chosen. Where files live is
        // not part of what a preset means — only how audio is processed is.
        let savedOutputDir = settings.outputDirectoryPath
        let savedDownloadDir = settings.downloadDirectoryPath
        let savedSessionRoot = settings.sessionRootPath
        settings = preset.settings
        settings.outputDirectoryPath = savedOutputDir
        settings.downloadDirectoryPath = savedDownloadDir
        settings.sessionRootPath = savedSessionRoot
        presetStore.selectedPresetID = preset.id
    }

    func saveCurrentAsPreset(name: String) {
        presetStore.savePreset(name: name, settings: settings)
    }

    // MARK: - File management

    /// Stable identity for a file on disk. The same file arrives spelled
    /// differently depending on how it got here — a drag gives /var/…, a
    /// directory scan gives /private/var/… — and rows must not double up over
    /// spelling. Compare with this, never with URL ==.
    private nonisolated static func fileIdentity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Audio inside a dropped folder, name-ordered, at any depth. Downloads are
    /// filed one clip per folder, so dropping a folder — one clip's, or a whole
    /// show's worth of them — has to mean "everything in here".
    private static func audioFiles(inFolder folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let found = enumerator.compactMap { $0 as? URL }
            .filter { validExtensions.contains($0.pathExtension.lowercased()) }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func addFiles(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        let loose = fileURLs.filter { !$0.hasDirectoryPath }
        let folders = fileURLs.filter(\.hasDirectoryPath)

        let fromLoose = loose.filter { Self.validExtensions.contains($0.pathExtension.lowercased()) }
        var fromFolders: [URL] = []
        var emptyFolders = 0
        for folder in folders {
            let audio = Self.audioFiles(inFolder: folder)
            if audio.isEmpty { emptyFolders += 1 } else { fromFolders.append(contentsOf: audio) }
        }

        // Dropping a folder and then one of its clips shouldn't double the row.
        let alreadyListed = Set(files.map { Self.fileIdentity($0.url) })
        var seen = Set<String>()
        let valid = (fromLoose + fromFolders).filter {
            let identity = Self.fileIdentity($0)
            return !alreadyListed.contains(identity) && seen.insert(identity).inserted
        }
        let badFormat = loose.count - fromLoose.count

        var notices: [String] = []
        if emptyFolders > 0 {
            notices.append("\(emptyFolders) folder\(emptyFolders == 1 ? "" : "s") skipped — no audio inside.")
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
        // A clip re-added days later, by drag or by folder drop, arrives with
        // the cut the session's notes file has for it.
        let records = downloadNotesFile.map { SessionNotesFile.read(at: $0) } ?? []
        let newFiles = urls.map { url -> FileItem in
            var item = FileItem(url: url)
            if let cut = records.first(where: { $0.filename == url.lastPathComponent })?.timestamp,
               !cut.isEmpty {
                item.cut = cut
            }
            return item
        }
        files.append(contentsOf: newFiles)

        for file in newFiles {
            analyzeFile(file)
            generateWaveform(file)
        }
    }

    /// Applies a channel override to `ids`, or clears it back to the settings
    /// panel with nil.
    ///
    /// Takes a set rather than one id so the context menu can act on a whole
    /// selection — the common case is marking several clips from the same
    /// source mono-left in one go.
    func setChannelMode(_ mode: ClipChannelMode?, for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for index in files.indices where ids.contains(files[index].id) {
            files[index].channelMode = mode
        }
    }

    /// The mode shared by every id in `ids`, or nil when they disagree or
    /// follow the panel. Drives the checkmark in the context menu.
    func commonChannelMode(for ids: Set<UUID>) -> ClipChannelMode? {
        let modes = Set(files.filter { ids.contains($0.id) }.map(\.channelMode))
        guard modes.count == 1 else { return nil }
        return modes.first ?? nil
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
    /// A trashed original has nothing left at `url` to rename.
    func isRenamable(_ file: FileItem) -> Bool {
        if file.originalTrashed { return false }
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

    // MARK: - Cuts

    /// Row whose cut is being set; non-nil drives the Set Cut alert.
    var cutTargetID: UUID?
    var cutField: String = ""

    /// A cut goes in the clip's file name, so a row takes one whenever its file
    /// can be renamed. The notes file is written too when there is one; a
    /// temporary session, which keeps none, gets the name alone.
    func canSetCut(_ file: FileItem) -> Bool { isRenamable(file) }

    func beginCut(_ id: UUID) {
        guard let file = files.first(where: { $0.id == id }), canSetCut(file) else { return }
        cutField = file.cut ?? ""
        cutTargetID = id
    }

    func cancelCut() {
        cutTargetID = nil
        cutField = ""
    }

    func confirmCut() {
        guard let id = cutTargetID else { return }
        setCut(cutField, for: id)
        cancelCut()
    }

    /// Sets a row's cut, or removes it when `rawCut` is empty. The file is
    /// renamed so its name ends with the new cut in place of the row's old one
    /// (`ClipCutName`), the row shows it, and the session's notes file records
    /// it under the new name.
    ///
    /// In the notes, a clip downloaded in this run is found by its link and
    /// anything else by its file name — so a clip renamed by hand after an
    /// earlier run's download gets a block of its own.
    func setCut(_ rawCut: String, for id: UUID) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        let cut = rawCut.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = files[index].url.lastPathComponent
        let stem = files[index].url.deletingPathExtension().lastPathComponent
        let newStem = ClipCutName.stem(ClipCutName.baseStem(stem, cut: files[index].cut ?? ""), cut: cut)

        let failure: String?
        switch renameFile(id: id, to: newStem) {
        case .renamed:
            failure = nil
        case .notRenamable:
            failure = "The cut goes in the clip's file name, which can't change while the clip is being analyzed or processed, or once it is in the Trash."
        case .invalidName:
            failure = "The cut leaves the clip with no usable file name."
        case .nameTaken:
            let ext = files[index].url.pathExtension
            failure = "A file named \"\(ext.isEmpty ? newStem : "\(newStem).\(ext)")\" already exists in the same folder."
        case .renameFailed(let message):
            failure = message
        }
        if let failure {
            alertTitle = "Cut Not Set"
            alertMessage = failure
            return
        }
        // The name carries the cut now, so the row shows it even if the notes
        // can't be written.
        files[index].cut = cut.isEmpty ? nil : cut

        guard let notesFile = downloadNotesFile else { return }
        let source = downloadedURLToFileID.first(where: { $0.value == id })?.key
        do {
            try SessionNotesFile.setCut(
                cut,
                filename: oldName,
                renamedTo: files[index].url.lastPathComponent,
                source: source,
                at: notesFile
            )
        } catch {
            alertTitle = "Notice"
            alertMessage = "The file is renamed, but the cut could not be written to the clip notes: \(error.localizedDescription)"
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
        /// The session's notes file has `url`, downloaded as `filename`, but
        /// that file has moved on — processed and trashed, or filed away by
        /// the clip skill. The popover asks before fetching it a second time.
        case alreadyDownloaded(url: String, filename: String)
    }

    var downloadURLField: String = ""
    /// Optional custom filename (stem only); blank keeps the source title.
    var downloadNameField: String = ""
    /// The cut to make, e.g. "1:13 to :55". It ends the downloaded file's name
    /// (`ClipCutName`) and is written on its own line in the session's notes
    /// file.
    var downloadTimestampField: String = ""
    /// "Trash Originals": move each source file to the Trash once its output is
    /// written. Deliberately NOT part of `ClipHackSettings` — that struct is what
    /// presets store and reapply, and switching preset must never quietly start
    /// deleting files. Persisted across launches.
    var trashOriginalsEnabled: Bool {
        didSet { ClipHackSettings.store.set(trashOriginalsEnabled, forKey: Self.trashOriginalsKey) }
    }
    private static let trashOriginalsKey = "trashOriginalsAfterProcessing"

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
        if !isDownloading {
            downloadState = .idle
        }
        isDownloadPopoverPresented = true
        return true
    }

    /// A different link typed or pasted over one ClipHack was asking about
    /// takes the question away with it.
    func downloadURLFieldChanged() {
        if case .alreadyDownloaded = downloadState { downloadState = .idle }
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

    /// Folder name shown in the download popover's Destination row.
    var downloadDirectoryDisplayName: String {
        if isTemporarySession { return temporarySessionFolder.lastPathComponent }
        guard let path = settings.downloadDirectoryPath, !path.isEmpty else { return "Music/ClipHack" }
        return Self.folderDisplayName(path)
    }

    /// A chosen folder as the Destination row and OUTPUT DIR name it.
    ///
    /// Inside a session the leaf is always `clips`, which alone doesn't say
    /// whose — and the episode's name alone reads as the episode folder — so
    /// the two are shown together: `HT_0382 2026-09-22/clips`. One rule for
    /// both rows, so a session that points both at one folder reads the same
    /// in each.
    static func folderDisplayName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent == ClipSessionStore.clipsSubfolder else {
            return url.lastPathComponent
        }
        return url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
    }

    /// Full destination path, for the Destination row's tooltip.
    var downloadDirectoryDisplayPath: String { downloadDirectory.path }

    /// Resets the popover after a download starts, finishes, or turns out to be
    /// one we already have.
    private func clearDownloadForm() {
        downloadURLField = ""
        downloadNameField = ""
        downloadTimestampField = ""
        downloadState = .idle
        isDownloadPopoverPresented = false
    }

    /// The session's notes-file block for a clip downloaded from `url`, if
    /// there is one. Never in a temporary session, which keeps no notes file.
    func earlierDownload(of url: String, in destination: URL) -> ClipRecord? {
        guard !isTemporarySession else { return nil }
        return SessionNotesFile.read(at: sessionNotesURL(for: destination))
            .first { ClipRecord.isSameSource($0.sourceURL, url) }
    }

    /// A clip downloaded from `url` earlier is still on disk under the name it
    /// was downloaded with: put that file in the list and select it instead of
    /// fetching a second copy under a `-2` name. Returns true when it took
    /// over the download.
    ///
    /// Internal for unit tests.
    func adoptAlreadyDownloadedClip(for url: String, in destination: URL) -> Bool {
        guard let existing = earlierDownload(of: url, in: destination)
            .flatMap({ audioURL(for: $0, in: destination) })
        else {
            return false
        }

        let identity = Self.fileIdentity(existing)
        if let row = files.first(where: { Self.fileIdentity($0.url) == identity }) {
            selectedFileIDs = [row.id]
        } else {
            addFiles([existing])
            guard let row = files.last(where: { Self.fileIdentity($0.url) == identity }) else {
                return false
            }
            selectedFileIDs = [row.id]
        }

        downloadedURLToFileID[url] = selectedFileIDs.first
        alertTitle = "Already Downloaded"
        alertMessage = "\"\(existing.lastPathComponent)\" came from this link, so it's been added to the list instead of downloaded again."
        clearDownloadForm()
        return true
    }

    /// `again` is the popover's Download Again: it fetches a link the notes
    /// file already has, once ClipHack has said so.
    func startDownload(again: Bool = false) {
        guard !isDownloading else { return }
        guard let url = Self.validatedWebURL(downloadURLField) else {
            downloadState = .failed("Enter a valid http(s) URL.")
            return
        }

        if let existingID = existingDownloadRowID(for: url) {
            selectedFileIDs = [existingID]
            clearDownloadForm()
            return
        }

        // The week's prep clears the last episode's clips folder out, which
        // can happen while ClipHack is open — so move to the newest episode
        // first, and stop only if even that has nowhere to download to. A
        // temporary session isn't using the saved folder, so a missing one is
        // no reason to stop it.
        followNewestEpisode()
        if !isTemporarySession,
           YtDlpService.customDownloadDirectoryMissing(settings.downloadDirectoryPath) {
            downloadState = .failed("\"\(downloadDirectoryDisplayName)\" is gone, and the show folder has no episode to use instead. Choose Show Folder… in the session menu.")
            return
        }

        let destination = downloadDirectory
        // Read now, not when the download finishes, so switching session while
        // it runs can't file its block in another session's notes.
        let notesFile = downloadNotesFile

        // The row-level dedupe above only knows about this session. Clip prep
        // runs over days, so also ask the destination itself — the notes files
        // record what each clip came from.
        if adoptAlreadyDownloadedClip(for: url, in: destination) { return }
        // Its file has moved on since: processed, with the original trashed,
        // or renamed and filed by the clip skill. Fetching it again would hand
        // the skill a duplicate to process, so ask first.
        var confirmed = false
        if again, case .alreadyDownloaded(let asked, _) = downloadState { confirmed = asked == url }
        if !confirmed, let earlier = earlierDownload(of: url, in: destination) {
            downloadState = .alreadyDownloaded(url: url, filename: earlier.filename)
            return
        }
        // For a custom folder, prepare it in-app (correct permission attribution)
        // and surface a clear message if it isn't writable, before yt-dlp runs.
        // The default (~/Music/ClipHack) is created on demand inside downloadAudio.
        if isTemporarySession || settings.downloadDirectoryPath != nil,
           !YtDlpService.prepareWritableDirectory(destination) {
            downloadState = .failed(isTemporarySession
                ? temporarySessionRefusal
                : "ClipHack can't write to \"\(destination.lastPathComponent)\". Grant access in System Settings ▸ Privacy & Security ▸ Files and Folders.")
            return
        }

        let stem = YtDlpService.sanitizedStem(downloadNameField)
        let cut = downloadTimestampField
        downloadState = .downloading(progress: "Starting download…")

        // `[self]` states what the Task already did implicitly: it holds the view
        // model until the download ends. The progress handler below stays weak.
        downloadTask = Task { [self] in
            defer { downloadTask = nil }
            do {
                let path = try await YtDlpService.shared.downloadAudio(url: url, destination: destination, customStem: stem, cut: cut) { [weak self] line in
                    guard let self else { return }
                    Task { @MainActor in
                        // Stale lines can trail a finished/failed download —
                        // never let one overwrite a terminal state.
                        guard self.isDownloading else { return }
                        self.downloadState = .downloading(progress: line)
                    }
                }
                finishDownload(sourceURL: url, filePath: path, notesFile: notesFile)
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

    /// `finishDownload(sourceURL:filePath:notesFile:)` for a download started
    /// now. Internal for unit tests.
    func finishDownload(sourceURL: String, filePath: String) {
        finishDownload(sourceURL: sourceURL, filePath: filePath, notesFile: downloadNotesFile)
    }

    /// Feeds a completed download through the existing add-files path, then
    /// records and selects the row that landed, gives it its cut, and
    /// records the clip in `notesFile` — the notes file of the
    /// session the download was started in, nil when that was a temporary one.
    func finishDownload(sourceURL: String, filePath: String, notesFile: URL?) {
        let fileURL = URL(fileURLWithPath: filePath)
        addFiles([fileURL])
        // addFiles can reject (unsupported extension) or defer to the
        // reprocess warning — only record and select a row that landed.
        let identity = Self.fileIdentity(fileURL)
        guard let index = files.lastIndex(where: { Self.fileIdentity($0.url) == identity }) else {
            downloadState = .idle
            return
        }

        let cut = downloadTimestampField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cut.isEmpty {
            files[index].cut = cut
        }

        // Recorded in the session's own notes file, beside the audio.
        if let notesFile {
            do {
                // The filename, the cut and the source. The filename is written
                // even when it was typed by hand: it is the only line that says
                // which clip a block is. The source is what the file is matched
                // on, for replacing a block and for the already-downloaded check.
                let record = ClipRecord(
                    filename: fileURL.lastPathComponent,
                    timestamp: downloadTimestampField.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceURL: sourceURL
                )
                // The session's folder is the configured destination, not something
                // walked up from the file — a download that was not filed into a
                // folder of its own would land two levels too high.
                try SessionNotesFile.upsert(record, at: notesFile)
            } catch {
                alertTitle = "Notice"
                alertMessage = "Downloaded, but the clip notes could not be written: \(error.localizedDescription)"
            }
        }

        downloadedURLToFileID[sourceURL] = files[index].id
        selectedFileIDs = [files[index].id]
        clearDownloadForm()
    }

    // MARK: - Clip notes

    /// The folder a download lands in, which is where its notes are recorded.
    /// The session picker points this at an episode's own `clips` folder, so an
    /// episode's audio and its notes stay together with nothing else to set.
    /// A temporary session swaps its own folder in without saving it.
    var downloadDirectory: URL {
        if isTemporarySession { return temporarySessionFolder }
        return YtDlpService.resolveDownloadDirectory(settings.downloadDirectoryPath)
    }

    /// The session's one notes file, named after the session.
    func sessionNotesURL(for folder: URL) -> URL {
        SessionNotesFile.url(
            inClipsFolder: folder,
            title: ClipSessionStore.session(forClipsFolder: folder).title
        )
    }

    var sessionNotesURL: URL { sessionNotesURL(for: downloadDirectory) }

    /// The notes file downloads are recorded in and read back from: the
    /// session's own, or nil in a temporary session, which keeps none.
    var downloadNotesFile: URL? { isTemporarySession ? nil : sessionNotesURL }

    /// The clip's audio, when it is still in `folder` under the name its block
    /// records. A block with no filename cannot be located.
    func audioURL(for record: ClipRecord, in folder: URL) -> URL? {
        guard !record.filename.isEmpty else { return nil }
        let url = folder.appendingPathComponent(record.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Sessions

    /// Picker for the show root, injectable like the download one.
    var sessionRootPicker: () -> String? = {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Show Folder"
        panel.message = "Pick the folder your episode folders live in."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// The session the app is pointed at, read back from the download folder
    /// rather than stored — the folder is the session, so there is no second
    /// copy of that fact to fall out of date.
    ///
    /// nil while downloads go to the default location, which is not an episode
    /// of anything, and while a temporary session is open, which is not one
    /// either.
    var currentSession: ClipSession? {
        guard !isTemporarySession,
              let path = settings.downloadDirectoryPath, !path.isEmpty else { return nil }
        return ClipSessionStore.session(
            forClipsFolder: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    /// Window title: the session, or the app name before one is chosen.
    var sessionTitle: String {
        if isTemporarySession { return Self.temporarySessionTitle }
        return currentSession?.title ?? "ClipHack"
    }

    /// Shown under the window title — which show the open session belongs to,
    /// or the folder a temporary session files into. Empty when no session is
    /// open, which hides the subtitle entirely.
    var sessionSubtitle: String {
        if isTemporarySession { return temporarySessionFolder.lastPathComponent }
        guard currentSession != nil, let root = sessionRoot else { return "" }
        return root.lastPathComponent
    }

    var sessionRoot: URL? {
        guard let path = settings.sessionRootPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var sessionRootDisplayName: String {
        sessionRoot?.lastPathComponent ?? "No show folder"
    }

    /// Points ClipHack at the newest episode in the show folder, unless it
    /// already is or a temporary session is open.
    ///
    /// ClipHack makes no folders: the show's weekly prep makes the next
    /// episode and clears the last one's clips out, and ClipHack follows. Run
    /// at launch, whenever it comes forward, and before each download, so a
    /// new episode is picked up without being chosen and a cleared one is
    /// never downloaded into.
    func followNewestEpisode() {
        guard !isTemporarySession else { return }
        adoptSessionRootIfNeeded()
        guard let root = sessionRoot,
              let newest = ClipSessionStore.newestEpisode(inRoot: root) else { return }
        let target = ClipSessionStore.currentClipsFolder(for: newest).standardizedFileURL.path
        let current = settings.downloadDirectoryPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        }
        if current != target { openSession(newest) }
    }

    /// Points downloads and processed output at `session`'s clips folder.
    ///
    /// Both folders, deliberately. An episode's source audio, its notes and its
    /// finished WAVs belong in one place: that is what keeps an episode's notes
    /// file its own instead of a scratch folder's shared by every show, and
    /// what leaves an old episode still browsable months later.
    ///
    /// The clips folder is looked up again rather than taken from `session`,
    /// which the menu read when it built its list — possibly before the
    /// episode's `clips` folder existed.
    ///
    /// Opening an episode ends a temporary session.
    func openSession(_ session: ClipSession) {
        isTemporarySession = false
        let path = ClipSessionStore.currentClipsFolder(for: session).path
        settings.downloadDirectoryPath = path
        settings.outputDirectoryPath = path
        adoptSessionRootIfNeeded()
    }

    /// Presents the show-folder picker, persists the choice, and moves to its
    /// newest episode.
    @discardableResult
    func chooseSessionRoot() -> Bool {
        guard let path = sessionRootPicker() else { return false }
        // Absorb the easy mistake of picking the episode instead of the show.
        settings.sessionRootPath = ClipSessionStore.normalizedRoot(
            URL(fileURLWithPath: path, isDirectory: true)
        ).path
        followNewestEpisode()
        return true
    }

    /// Takes the show root to be the open episode's parent when none is set,
    /// so following the newest episode needs no setup step.
    private func adoptSessionRootIfNeeded() {
        guard settings.sessionRootPath?.isEmpty ?? true,
              let path = settings.downloadDirectoryPath, !path.isEmpty else { return }
        settings.sessionRootPath = ClipSessionStore.inferredRoot(
            forClipsFolder: URL(fileURLWithPath: path, isDirectory: true)
        ).path
    }

    // MARK: - Temporary session

    static let temporarySessionTitle = "Temporary Session"

    /// Where a temporary session files downloads and processed audio.
    /// Injectable so tests never write to the real Desktop.
    var temporarySessionFolder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)

    /// A session that is not an episode: downloads and processed audio go to
    /// `temporarySessionFolder`, and no notes file is kept.
    ///
    /// In memory only, and never written into `settings`. Those paths *are*
    /// the episode — pointing them at the Desktop would reopen there after a
    /// relaunch, adopt the home folder as the show, and start a `Desktop.txt`
    /// notes file — so the folder is swapped in wherever it is read instead,
    /// and a run gets it on its copy of the settings. Relaunching, or opening
    /// any episode, finds the one that was open exactly as it was left.
    private(set) var isTemporarySession = false

    /// Starts a temporary session. Returns false, with an alert, when its
    /// folder can't be written.
    ///
    /// The write is tried here, by the app itself: on a Mac where ClipHack has
    /// not yet been let into the Desktop, macOS asks now, naming ClipHack,
    /// instead of when ffmpeg or yt-dlp first writes there mid-job.
    @discardableResult
    func openTemporarySession() -> Bool {
        guard YtDlpService.prepareWritableDirectory(temporarySessionFolder) else {
            alertTitle = "Temporary Session Unavailable"
            alertMessage = temporarySessionRefusal
            return false
        }
        isTemporarySession = true
        return true
    }

    /// Goes back to the episode — the newest, should prep have made another
    /// in the meantime.
    func closeTemporarySession() {
        isTemporarySession = false
        followNewestEpisode()
    }

    private var temporarySessionRefusal: String {
        "ClipHack can't write to \"\(temporarySessionFolder.lastPathComponent)\". Grant access in System Settings ▸ Privacy & Security ▸ Files and Folders."
    }

    /// The settings a run processes with: the saved ones, with a temporary
    /// session's folder standing in for the output folder. A copy, never saved.
    var processingSettings: ClipHackSettings {
        var copy = settings
        if isTemporarySession {
            copy.outputDirectoryPath = temporarySessionFolder.path
        }
        return copy
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

        // Taken once, so the checks below and the run itself agree on where
        // output goes — a temporary session's folder included.
        let runSettings = processingSettings

        if let customPath = runSettings.outputDirectoryPath {
            // A temporary session's folder is the Desktop, where what decides
            // is macOS's privacy setting, so it is asked with a real write —
            // the same one that let the session start.
            let writable = isTemporarySession
                ? YtDlpService.prepareWritableDirectory(URL(fileURLWithPath: customPath, isDirectory: true))
                : FileManager.default.isWritableFile(atPath: customPath)
            if !writable {
                alertTitle = "Error"
                alertMessage = isTemporarySession
                    ? temporarySessionRefusal
                    : "Output directory is not writable: \(customPath)"
                return
            }
        }

        // The output is named after the input, cut and all: the cut is made
        // on the processed clip, so its name has to carry it.
        let inputs = processable.map { JobInput(id: $0.id, url: $0.url, channelMode: $0.channelMode) }
        var outputWarnings: [String] = []
        let outputDirectories = inputs.map { input in
            OutputDirectory.clipHackOutputDirectory(for: input.url, settings: runSettings) { warning in
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

        for i in files.indices {
            if case .ready(let stats) = files[i].status {
                files[i].analysisStats = stats
            }
        }

        // `[self]` states what the Task already did implicitly: it holds the view
        // model for the whole run. `onFileStarted` below still captures it weakly.
        processingTask = Task { [self] in
            do {
                let processor = AudioProcessor(
                    settings: runSettings,
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

                let trashRefusals = trashOriginalsEnabled
                    ? trashOriginals(for: batch.successes)
                    : []

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

                // The audio came out fine in every one of these cases, so they ride
                // along with whatever the run already had to say.
                if !trashRefusals.isEmpty {
                    let notice = "Processed, but these originals stayed put:\n"
                        + trashRefusals.joined(separator: "\n")
                    if let existing = alertMessage {
                        alertMessage = existing + "\n\n" + notice
                    } else {
                        alertTitle = "Notice"
                        alertMessage = notice
                    }
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

    /// Moves each successfully processed source file to the Trash and marks its row.
    ///
    /// Returns one line per source it declined to trash. Those are notices, not
    /// failures: the output is already written, so the run succeeded either way.
    func trashOriginals(
        for successes: [JobResult],
        trash: (URL, URL) -> OriginalFileTrash.Refusal? = {
            OriginalFileTrash.trash(original: $0, output: $1)
        }
    ) -> [String] {
        var refusals: [String] = []
        for result in successes {
            guard let index = files.firstIndex(where: { $0.id == result.id }) else { continue }
            switch trash(result.input, result.output) {
            case nil, .originalMissing:
                // Missing counts as trashed — either way it is no longer there.
                files[index].originalTrashed = true
            case .outputIsOriginal, .outputNotUsable:
                refusals.append("\(result.input.lastPathComponent) — could not confirm the processed file on disk.")
            case .trashFailed(let message):
                refusals.append("\(result.input.lastPathComponent) — \(message)")
            }
        }
        return refusals
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
                if let failure = try await AudioStreamProbe.probe(ffprobe: tools.ffprobe, url: file.url).failure {
                    if let currentIndex = files.firstIndex(where: { $0.id == file.id }) {
                        files[currentIndex].status = .error(failure.localizedDescription)
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
