import Foundation

enum ClipHackOutputNaming {
    /// ClipHack outputs: `{name}-{44k|48k}{norm-}clipped-{limit}dB.wav`
    nonisolated static func looksLikeClipHackOutput(_ url: URL) -> Bool {
        let base = url.deletingPathExtension().lastPathComponent
        return base.range(
            of: #"\d{2}k(norm-)?clipped-"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
