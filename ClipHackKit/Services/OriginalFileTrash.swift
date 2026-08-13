import Foundation

/// Moves a source file to the Trash once its processed result is safely on disk.
///
/// Trash rather than delete: processing is lossy and settings-dependent, so a
/// bad result has to stay recoverable from the Finder.
enum OriginalFileTrash {

    enum Refusal: Equatable, Sendable {
        /// The source is already gone — nothing to do, and not an error.
        case originalMissing
        /// The processed result isn't on disk (or is empty), so the source is
        /// still the only copy of this audio.
        case outputNotUsable
        /// Source and result are the same file. Trashing would destroy the output.
        case outputIsOriginal
        /// The volume refused the move — network shares and some external disks
        /// have no Trash.
        case trashFailed(String)
    }

    /// Trashes `original`, but only once `output` is proven to exist and be non-empty.
    ///
    /// Every refusal leaves the source untouched; callers report them rather than
    /// treating them as processing failures, since the audio itself came out fine.
    static func trash(
        original: URL,
        output: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        fileSize: (URL) -> Int = { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0
        },
        trashItem: (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) -> Refusal? {
        guard fileExists(original) else { return .originalMissing }

        // Symlinks and /tmp-style aliases mean two different-looking URLs can name
        // one file; compare resolved paths before destroying anything.
        let originalPath = original.resolvingSymlinksInPath().standardizedFileURL.path
        let outputPath = output.resolvingSymlinksInPath().standardizedFileURL.path
        guard originalPath != outputPath else { return .outputIsOriginal }

        guard fileExists(output), fileSize(output) > 0 else { return .outputNotUsable }

        do {
            try trashItem(original)
            return nil
        } catch {
            return .trashFailed(error.localizedDescription)
        }
    }
}
