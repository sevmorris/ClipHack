import Foundation

/// Anchors resource lookup to the ClipHackKit framework bundle — where the
/// vendored ffmpeg/ffprobe/yt-dlp binaries now live — regardless of the host
/// process's `Bundle.main`. This is what lets the tools resolve both inside
/// the app (embedded framework) and in host-less unit tests (linked framework),
/// where `Bundle.main` would otherwise be the xctest runner.
enum KitBundle {
    private final class Token {}
    static let resources = Bundle(for: Token.self)
}
