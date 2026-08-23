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
        self.clipNotesEnabled = ClipHackSettings.store.bool(forKey: Self.clipNotesKey)
        // Defaults to on, so `bool(forKey:)`'s false-when-absent is wrong here.
        self.trashOriginalsEnabled =
            ClipHackSettings.store.object(forKey: Self.trashOriginalsKey) as? Bool ?? true
        let storedHeight = ClipHackSettings.store.double(forKey: Self.notesFieldHeightKey)
        // 0 means "never set" — UserDefaults has no distinct absent value for Double.
        self.notesFieldHeight = storedHeight == 0
            ? Self.defaultNotesFieldHeight
            : Self.clampedNotesFieldHeight(storedHeight)
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
        // Notes live on disk beside the audio, so a clip re-added days later —
        // in a new session, by drag or by folder drop — still arrives with the
        // text that says what it is.
        let newFiles = urls.map { url -> FileItem in
            var item = FileItem(url: url)
            if let notes = ClipNotesFile.read(forAudioFile: url)?.notes, !notes.isEmpty {
                item.notes = notes
            }
            return item
        }
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
    /// Optional free-text carried onto the added row and into the notes file.
    /// Line one becomes this clip's list description; anything typed below it
    /// is scratch (timings) and rides along untouched.
    var downloadNotesField: String = ""
    /// Who is *in* the clip — the speaker, not whoever posted it. Auto-filled
    /// from the post's own text when a name can be read confidently, left blank
    /// when it can't.
    var downloadPersonField: String = ""
    /// "Save clip notes": write a notes sidecar into each download's own clip
    /// folder. Persisted across launches.
    var clipNotesEnabled: Bool {
        didSet { ClipHackSettings.store.set(clipNotesEnabled, forKey: Self.clipNotesKey) }
    }
    /// Key predates the per-clip notes file (it gated the daily clip list this
    /// replaced) — kept as-is so the preference survives the upgrade.
    private static let clipNotesKey = "clipListEnabled"

    /// "Trash Originals": move each source file to the Trash once its output is
    /// written. Deliberately NOT part of `ClipHackSettings` — that struct is what
    /// presets store and reapply, and switching preset must never quietly start
    /// deleting files. Persisted across launches.
    var trashOriginalsEnabled: Bool {
        didSet { ClipHackSettings.store.set(trashOriginalsEnabled, forKey: Self.trashOriginalsKey) }
    }
    private static let trashOriginalsKey = "trashOriginalsAfterProcessing"

    static let minNotesFieldHeight: Double = 56
    static let maxNotesFieldHeight: Double = 360
    static let defaultNotesFieldHeight: Double = 96
    private static let notesFieldHeightKey = "downloadNotesFieldHeight"

    static func clampedNotesFieldHeight(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultNotesFieldHeight }
        return min(max(raw, minNotesFieldHeight), maxNotesFieldHeight)
    }

    /// Height of the popover's Notes box in points — the user drags the grip in
    /// its bottom-right corner to resize. Clamped on write (a drag can run past
    /// either end) and persisted across launches.
    var notesFieldHeight: Double {
        didSet {
            let clamped = Self.clampedNotesFieldHeight(notesFieldHeight)
            // Assigning inside didSet doesn't re-enter it, so this settles here.
            if clamped != notesFieldHeight { notesFieldHeight = clamped }
            ClipHackSettings.store.set(notesFieldHeight, forKey: Self.notesFieldHeightKey)
        }
    }
    var isDownloadPopoverPresented = false
    var downloadState: DownloadState = .idle

    var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    private var downloadTask: Task<Void, Never>?
    /// Source URL → file-browser row added for it, for session-scoped dedupe.
    private var downloadedURLToFileID: [String: UUID] = [:]

    /// Injectable so the prefill guards are testable without network.
    var postTextFetcher: @Sendable (String) async -> String? = { await XPostText.fetchPostText(for: $0) }
    /// The in-flight X-post-text fetch, exposed so tests can await it.
    private(set) var notesFetchTask: Task<Void, Never>?
    /// The X status ID we last kicked off a Notes fetch for. Lets us dedupe so
    /// editing or re-entering the same post's URL (trailing query params,
    /// whitespace) doesn't refetch on every keystroke. nil when the field holds
    /// no X post URL.
    private var lastPrefilledStatusID: String?
    /// The exact Notes text a fetch auto-filled, so we can tell machine-written
    /// notes (safe to refresh when the URL moves to a new post) from notes the
    /// user has typed or edited (never touched). nil once the user edits them or
    /// we clear them.
    private var autoFilledNotes: String?
    /// The same idea for Person: what a fetch filled, so moving the URL to a
    /// different post can drop machine-written text without ever clearing a
    /// name the user typed.
    private var autoFilledPerson: String?

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
        prefillNotesFromURL(url)
        return true
    }

    /// Convenience when the popover opens: prefill an empty URL field from the
    /// pasteboard if it holds a plausible web URL. Never starts the download.
    func prefillDownloadFromPasteboard() {
        guard downloadURLField.isEmpty,
              let pasted = NSPasteboard.general.string(forType: .string),
              let url = Self.validatedWebURL(pasted) else { return }
        downloadURLField = url
        prefillNotesFromURL(url)
    }

    /// Called whenever the URL field's text changes — typing, pasting (⌘V), or
    /// editing. Fetches Notes for a newly-entered X post, and when the field
    /// moves off the post it was on (edited to a different post, a non-X link,
    /// or cleared) drops any Notes a previous auto-fill left behind. Gated to X
    /// post URLs and deduped by status ID, so hand-typing or tweaking a URL
    /// doesn't spawn a fetch on every keystroke.
    ///
    /// Deliberately NOT time-debounced (decision settled 2026-07-06 — don't
    /// reopen without new evidence). The statusID gate + status-ID dedupe
    /// already cover every realistic input: paste drops the whole URL at once
    /// (one fetch), non-status/non-X text never fetches, and editing that keeps
    /// the same status ID (trailing params, whitespace) is deduped. The only
    /// case a debounce would add is hand-typing a 19-digit tweet ID digit by
    /// digit — not a real workflow, and each keystroke's fetch cancels the prior
    /// one anyway, so there's no real cost. A debounce would only add timer
    /// state and untestable timing to the synchronous, unit-tested path here.
    func downloadURLFieldChanged() {
        if XPostText.statusID(from: downloadURLField) != nil {
            prefillNotesFromURL(downloadURLField)
        } else {
            lastPrefilledStatusID = nil
            notesFetchTask?.cancel()
            discardStaleAutoFilledNotes()
        }
    }

    /// Best-effort: when `urlString` is an X/Twitter post, fetch its body text
    /// and drop it into Notes — but only if Notes is still empty when the fetch
    /// resolves and the URL field still holds this URL (never clobber typed
    /// notes, never attach a stale post's text). Deduped by status ID so the
    /// same post isn't refetched, and it first drops any Notes a *previous*
    /// auto-fill left behind for a different post. Fire-and-forget: it runs
    /// independently of the download and every failure is silent.
    func prefillNotesFromURL(_ urlString: String) {
        guard let id = XPostText.statusID(from: urlString), id != lastPrefilledStatusID else { return }
        lastPrefilledStatusID = id
        discardStaleAutoFilledNotes()
        notesFetchTask?.cancel()
        let fetch = postTextFetcher
        notesFetchTask = Task { [weak self] in
            let text = await fetch(urlString)
            self?.applyFetchedNotes(text, for: urlString)
        }
    }

    /// Applies a fetched post body to Notes, honoring both guards: only fill if
    /// Notes is still empty (never clobber typed text) and the URL field still
    /// holds the URL this text was fetched for (never attach a stale post's
    /// text). Records what it filled so a later URL change can tell this
    /// machine-written text from notes the user goes on to edit. Split out from
    /// the fetch Task so the guards are testable synchronously.
    func applyFetchedNotes(_ text: String?, for urlString: String) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              downloadURLField == urlString,
              downloadNotesField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // The account that posted a clip is usually not the person in it, so
        // the name is read out of the post's own text and left empty when it
        // can't be read confidently — a wrong name reads as correct.
        let (person, description) = ClipPersonName.extract(fromPostText: text)
        downloadNotesField = description
        autoFilledNotes = description
        if let person, downloadPersonField.trimmingCharacters(in: .whitespaces).isEmpty {
            downloadPersonField = person
            autoFilledPerson = person
        }
    }

    /// Clears Notes only when they still hold exactly what a previous auto-fill
    /// wrote — i.e. the user hasn't typed or edited them since. Protects
    /// user-authored notes while letting stale machine-filled text refresh for
    /// a new post.
    private func discardStaleAutoFilledNotes() {
        if let auto = autoFilledNotes, downloadNotesField == auto {
            downloadNotesField = ""
            autoFilledNotes = nil
        }
        // Checked separately: the user may have rewritten one field and left
        // the other exactly as the fetch filled it.
        if let auto = autoFilledPerson, downloadPersonField == auto {
            downloadPersonField = ""
            autoFilledPerson = nil
        }
    }

    /// Resets the X-post Notes auto-fill bookkeeping when the download form is
    /// cleared, so the next URL entered isn't deduped against a finished one and
    /// no stale sentinel lingers.
    private func resetNotesAutoFillState() {
        lastPrefilledStatusID = nil
        autoFilledNotes = nil
        autoFilledPerson = nil
    }

    /// The row previously added for `sourceURL`, if it is still in the list.
    func existingDownloadRowID(for sourceURL: String) -> UUID? {
        guard let id = downloadedURLToFileID[sourceURL],
              files.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Folder name shown in the download popover's Destination row.
    var downloadDirectoryDisplayName: String {
        guard let path = settings.downloadDirectoryPath, !path.isEmpty else { return "Music/ClipHack" }
        let url = URL(fileURLWithPath: path)
        // Inside a session the leaf is always "clips", which names nothing —
        // show the episode that folder belongs to instead.
        if url.lastPathComponent == ClipSessionStore.clipsSubfolder {
            return url.deletingLastPathComponent().lastPathComponent
        }
        return url.lastPathComponent
    }

    /// Full destination path, for the Destination row's tooltip.
    var downloadDirectoryDisplayPath: String {
        YtDlpService.resolveDownloadDirectory(settings.downloadDirectoryPath).path
    }

    /// The folder-picker itself, injectable so the re-prompt flow is testable
    /// without a modal panel. Returns the chosen folder path, or nil on cancel.
    var downloadDirectoryPicker: () -> String? = {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Download Destination"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// Presents the folder picker and persists the choice. Returns true if the
    /// user picked a folder (also used by the missing-folder re-prompt).
    @discardableResult
    func chooseDownloadDirectory() -> Bool {
        guard let path = downloadDirectoryPicker() else { return false }
        settings.downloadDirectoryPath = path
        adoptSessionRootIfNeeded()
        loadSessions()
        return true
    }

    /// Reverts the download destination to the default (~/Music/ClipHack).
    func resetDownloadDirectory() {
        settings.downloadDirectoryPath = nil
    }

    /// Resets the popover after a download starts, finishes, or turns out to be
    /// one we already have.
    private func clearDownloadForm() {
        downloadURLField = ""
        downloadNameField = ""
        downloadNotesField = ""
        downloadPersonField = ""
        resetNotesAutoFillState()
        downloadState = .idle
        isDownloadPopoverPresented = false
    }

    /// A clip downloaded from `url` in an earlier session is still on disk:
    /// put that file in the list and select it instead of fetching a second
    /// copy under a `-2` name. Returns true when it took over the download.
    ///
    /// Internal for unit tests.
    func adoptAlreadyDownloadedClip(for url: String, in destination: URL) -> Bool {
        guard let existing = ClipNotesFile.existingClip(forSourceURL: url, in: destination) else {
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

    func startDownload() {
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

        // A custom download folder can vanish (moved, deleted, drive unmounted).
        // Re-prompt for one rather than failing or silently using the default;
        // if the user cancels, don't proceed.
        if YtDlpService.customDownloadDirectoryMissing(settings.downloadDirectoryPath) {
            guard chooseDownloadDirectory() else {
                downloadState = .failed("Choose a destination folder to download.")
                return
            }
        }

        let destination = YtDlpService.resolveDownloadDirectory(settings.downloadDirectoryPath)

        // The row-level dedupe above only knows about this session. Clip prep
        // runs over days, so also ask the destination itself — the notes files
        // record what each clip came from.
        if adoptAlreadyDownloadedClip(for: url, in: destination) { return }
        // For a custom folder, prepare it in-app (correct permission attribution)
        // and surface a clear message if it isn't writable, before yt-dlp runs.
        // The default (~/Music/ClipHack) is created on demand inside downloadAudio.
        if settings.downloadDirectoryPath != nil,
           !YtDlpService.prepareWritableDirectory(destination) {
            downloadState = .failed("ClipHack can't write to \"\(destination.lastPathComponent)\". Grant access in System Settings ▸ Privacy & Security ▸ Files and Folders, or choose another folder.")
            return
        }

        let stem = YtDlpService.sanitizedStem(downloadNameField)
        downloadState = .downloading(progress: "Starting download…")

        downloadTask = Task {
            defer { downloadTask = nil }
            do {
                let path = try await YtDlpService.shared.downloadAudio(url: url, destination: destination, customStem: stem) { [weak self] line in
                    guard let self else { return }
                    Task { @MainActor in
                        // Stale lines can trail a finished/failed download —
                        // never let one overwrite a terminal state.
                        guard self.isDownloading else { return }
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
    /// records and selects the row that landed, attaches notes, and writes the
    /// clip's notes file when enabled. Internal for unit tests.
    func finishDownload(sourceURL: String, filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        addFiles([fileURL])
        // addFiles can reject (unsupported extension) or defer to the
        // reprocess warning — only record and select a row that landed.
        let identity = Self.fileIdentity(fileURL)
        guard let index = files.lastIndex(where: { Self.fileIdentity($0.url) == identity }) else {
            downloadState = .idle
            return
        }

        // Line one of the sidecar's notes is this clip's list entry —
        // "Person — what they said" — and anything typed below it is kept as-is.
        let box = ClipListEntry.splitNotesBox(
            downloadNotesField.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let notes = ClipListEntry.compose(
            person: downloadPersonField.trimmingCharacters(in: .whitespaces),
            description: box.description,
            extra: box.extra
        )
        if !notes.isEmpty {
            files[index].notes = notes
        }

        // The download already landed in its own clip folder, so this writes the
        // sidecar right beside it.
        if clipNotesEnabled {
            do {
                try ClipNotesFile.write(notes: notes, sourceURL: sourceURL, forAudioFile: fileURL)
            } catch {
                alertTitle = "Notice"
                alertMessage = "Downloaded, but the clip notes could not be written: \(error.localizedDescription)"
            }
        }

        downloadedURLToFileID[sourceURL] = files[index].id
        selectedFileIDs = [files[index].id]
        clearDownloadForm()
    }

    // MARK: - Clip list

    /// One clip's line in the list panel, backed by its notes sidecar.
    ///
    /// Identified by the sidecar URL rather than the audio path: the audio can
    /// be renamed, processed, or trashed out from under a row, and the sidecar
    /// is the thing that persists.
    struct ClipListRow: Identifiable, Equatable {
        let id: URL
        var person: String
        var description: String
        /// Lines below the list line — timings, scratch. Round-tripped verbatim.
        var extra: String
        var filename: String
        var sourceURL: String
        /// False once the clip's audio is gone but its notes remain, which is
        /// normal late in a show's prep.
        var hasAudio: Bool
    }

    var isClipListPresented = false
    var clipListRows: [ClipListRow] = []

    /// The folder the clip list reads, which is wherever downloads go. Pointing
    /// ClipHack at an episode's own folder therefore scopes the list to that
    /// episode — there is no separate notion of a show to keep in sync.
    var clipListDirectory: URL {
        YtDlpService.resolveDownloadDirectory(settings.downloadDirectoryPath)
    }

    /// Rebuilds the rows from the sidecars on disk. Cheap enough to call on
    /// every panel open — a show is tens of small text files.
    func loadClipList() {
        clipListRows = ClipNotesFile.entries(in: clipListDirectory).map { entry in
            let parsed = ClipListEntry.parse(notes: entry.record.notes)
            return ClipListRow(
                id: entry.sidecar,
                person: parsed.person,
                description: parsed.description,
                extra: parsed.extra,
                filename: entry.record.filename,
                sourceURL: entry.record.sourceURL,
                hasAudio: entry.audio != nil
            )
        }
    }

    /// Writes one row back to its sidecar.
    ///
    /// Called on every keystroke rather than on commit, so there is never an
    /// edit living only in memory: prep runs over days and the panel is the
    /// list, so a lost edit is a lost clip. Each save is an atomic write of a
    /// file well under a kilobyte.
    func saveClipListRow(_ row: ClipListRow) {
        guard let index = clipListRows.firstIndex(where: { $0.id == row.id }) else { return }
        clipListRows[index] = row
        do {
            try ClipNotesFile.updateNotes(
                ClipListEntry.compose(
                    person: row.person,
                    description: row.description,
                    extra: row.extra
                ),
                atSidecar: row.id
            )
        } catch {
            alertTitle = "Notice"
            alertMessage = "Couldn't save notes for \"\(row.filename)\": \(error.localizedDescription)"
        }
    }

    /// The finished numbered list for the rows currently loaded.
    var clipListText: String {
        ClipListEntry.numberedList(
            clipListRows.map {
                ClipListEntry.Parsed(person: $0.person, description: $0.description)
            }
        )
    }

    /// Puts the numbered clip list on the clipboard, returning how many entries
    /// went with it.
    ///
    /// Reads from disk first. Every panel edit is already written through, so
    /// the sidecars are the truth, and this way the shortcut works whether or
    /// not the panel has ever been opened this session.
    @discardableResult
    func copyClipList() -> Int {
        loadClipList()
        let text = clipListText
        guard !text.isEmpty else {
            alertTitle = "Nothing to Copy"
            alertMessage = "No clip notes were found in \"\(clipListDirectory.lastPathComponent)\". Clips get a notes file when \"Save clip notes\" is on in the download popover."
            return 0
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text.components(separatedBy: "\n").count
    }

    // MARK: - Sessions

    /// Episode folders under the show root, newest first.
    var savedSessions: [ClipSession] = []

    /// Injectable so session naming is testable without the wall clock.
    var now: @Sendable () -> Date = { Date() }

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
    /// of anything.
    var currentSession: ClipSession? {
        guard let path = settings.downloadDirectoryPath, !path.isEmpty else { return nil }
        return ClipSessionStore.session(
            forClipsFolder: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    /// Window title: the session, or the app name before one is chosen.
    var sessionTitle: String { currentSession?.title ?? "ClipHack" }

    var sessionRoot: URL? {
        guard let path = settings.sessionRootPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var sessionRootDisplayName: String {
        sessionRoot?.lastPathComponent ?? "No show folder"
    }

    func loadSessions() {
        guard let root = sessionRoot else {
            savedSessions = []
            return
        }
        savedSessions = ClipSessionStore.sessions(inRoot: root)
    }

    /// Points downloads, processed output, and the clip list at `session`.
    ///
    /// Both folders, deliberately. An episode's source audio, its notes
    /// sidecars and its finished WAVs belong in one place: that is what makes
    /// the clip list scoped to a single episode instead of to a scratch folder
    /// shared by all of them, and what leaves an old episode still browsable
    /// months later. Output lands flat in the folder while sources sit in their
    /// own per-clip subfolders, so the folder Logic imports from stays legible.
    func openSession(_ session: ClipSession) {
        let path = session.clipsFolder.path
        settings.downloadDirectoryPath = path
        settings.outputDirectoryPath = path
        adoptSessionRootIfNeeded()
        loadClipList()
        loadSessions()
    }

    /// The title to offer for a new session: next episode number, today's date.
    var suggestedSessionTitle: String {
        guard let root = sessionRoot else {
            return "\(ClipSessionStore.defaultPrefix)_0001 \(ClipSessionStore.dateString(now()))"
        }
        return ClipSessionStore.nextTitle(inRoot: root, date: now())
    }

    /// Creates `<root>/<title>/clips` and switches to it. Returns false when
    /// there is no root to create in, or the folder can't be made.
    @discardableResult
    func createSession(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let root = sessionRoot else {
            alertTitle = "Choose a Show Folder"
            alertMessage = "Pick the folder your episode folders live in before creating a session."
            return false
        }
        do {
            let session = try ClipSessionStore.create(title: trimmed, inRoot: root)
            openSession(session)
            return true
        } catch {
            alertTitle = "Error"
            alertMessage = "Couldn't create \"\(trimmed)\": \(error.localizedDescription)"
            return false
        }
    }

    /// Presents the show-folder picker and persists the choice.
    @discardableResult
    func chooseSessionRoot() -> Bool {
        guard let path = sessionRootPicker() else { return false }
        settings.sessionRootPath = path
        loadSessions()
        return true
    }

    /// Adopts a show root the first time a session folder is chosen, so the
    /// session list works without a separate setup step: the root is simply
    /// the episode folder's parent.
    private func adoptSessionRootIfNeeded() {
        guard settings.sessionRootPath?.isEmpty ?? true,
              let path = settings.downloadDirectoryPath, !path.isEmpty else { return }
        settings.sessionRootPath = ClipSessionStore.inferredRoot(
            forClipsFolder: URL(fileURLWithPath: path, isDirectory: true)
        ).path
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
