import Foundation

extension FileManager {
    /// App-scoped scratch directory inside NSTemporaryDirectory.
    nonisolated static var cliphackTempDirectory: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("io.github.sevmorris.ClipHack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
