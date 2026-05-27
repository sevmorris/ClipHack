import Foundation

enum ClipHackFilename {
    /// Formats a limiter ceiling value as a filename tag (e.g. `1dB`).
    nonisolated static func formatDbTag(_ db: Double) -> String {
        var s = String(format: "%.2f", abs(db))
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
        }
        return "\(s)dB"
    }

    /// Returns `url` unchanged if free, otherwise appends ` (1)`, ` (2)`, …
    nonisolated static func uniqueOutputURL(_ url: URL, fm: FileManager = .default) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var counter = 1
        while true {
            let candidate = dir.appendingPathComponent("\(stem) (\(counter)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
