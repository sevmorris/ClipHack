import Foundation

/// An uncut copy of each processed clip, kept in an `orig` folder beside it.
///
/// The cut is made by hand on the processed WAV, so the copy is what a cut
/// that went wrong is redone from. `orig` sits inside the episode's clips
/// folder: the show's clip skill takes only files lying directly in `clips/`,
/// so it never sees the copies, and the week's prep clears them out with the
/// rest of the episode.
///
/// `nonisolated`: file handling only, called once per finished clip.
nonisolated enum ProcessedBackup {

    static let folderName = "orig"

    /// Copies `output` into the `orig` folder beside it, making the folder if
    /// needed, and returns the copy. A file already there under that name is
    /// kept, and this copy takes a ` (1)`-style name instead. On APFS the copy
    /// is a clone, so it takes no extra space until one of the two is edited.
    @discardableResult
    static func copy(_ output: URL, fileManager fm: FileManager = .default) throws -> URL {
        let folder = output.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = ClipHackFilename.uniqueOutputURL(
            folder.appendingPathComponent(output.lastPathComponent), fm: fm
        )
        try fm.copyItem(at: output, to: target)
        return target
    }
}
