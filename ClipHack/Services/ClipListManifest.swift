import Foundation

/// Plain-text daily clip list: filename / notes (blank line if empty) /
/// source URL, entries separated by a blank line — the same format as
/// WireHack's clip-list files so the two apps' logs read alike.
enum ClipListManifest {
    static func manifestFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "clip-list-\(formatter.string(from: date)).txt"
    }

    /// Three-line entry plus a trailing blank separator. Empty notes are
    /// written as a blank line so the entry structure stays predictable;
    /// multiline notes are kept verbatim (the separator still delimits).
    static func entry(filename: String, notes: String, sourceURL: String) -> String {
        "\(filename)\n\(notes)\n\(sourceURL)\n\n"
    }

    /// Appends `entry` to the daily manifest in `directory`, creating the
    /// file on first write.
    static func append(entry: String, in directory: URL, date: Date = Date()) throws {
        let manifestURL = directory.appendingPathComponent(manifestFilename(for: date))
        guard let data = entry.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let handle = try FileHandle(forWritingTo: manifestURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: manifestURL, options: .atomic)
        }
    }
}
