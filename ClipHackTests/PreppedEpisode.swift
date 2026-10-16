import Foundation
@testable import ClipHackKit

/// What the show's weekly prep leaves in `root`: `<title>/clips`. ClipHack
/// makes no episode folders itself, so tests make them here.
@MainActor
@discardableResult
func makePreppedEpisode(_ title: String, in root: URL) throws -> ClipSession {
    let folder = root.appendingPathComponent(title, isDirectory: true)
    let clips = folder.appendingPathComponent(ClipSessionStore.clipsSubfolder, isDirectory: true)
    try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
    return ClipSession(folder: folder, clipsFolder: clips)
}
