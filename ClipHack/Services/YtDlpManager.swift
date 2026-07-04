import Foundation

actor YtDlpManager {
    private var cachedPath: String?

    static let shared = YtDlpManager()

    private init() {}

    func ensureTool() throws -> String {
        if let path = cachedPath {
            return path
        }

        let path = try locateTool()
        cachedPath = path
        return path
    }

    /// Directory containing the bundled ffmpeg/ffprobe, suitable for yt-dlp's
    /// --ffmpeg-location (which accepts a directory and picks up both tools).
    func ffmpegDirectory() async throws -> String {
        let tools = try await FFmpegManager.shared.ensureTools()
        return URL(fileURLWithPath: tools.ffmpeg).deletingLastPathComponent().path
    }

    private func locateTool() throws -> String {
        let fm = FileManager.default

        if let toolURL = Bundle.main.url(forResource: "yt-dlp", withExtension: nil),
           fm.fileExists(atPath: toolURL.path) {
            return toolURL.path
        }

        if let resourceURL = Bundle.main.resourceURL {
            let toolURL = resourceURL.appendingPathComponent("yt-dlp")
            if fm.fileExists(atPath: toolURL.path) {
                return toolURL.path
            }
        }

        return try copyToTemp()
    }

    private func copyToTemp() throws -> String {
        let fm = FileManager.default
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ClipHack/bin", isDirectory: true)

        try fm.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let toolDst = tempBase.appendingPathComponent("yt-dlp")

        try copyResource("yt-dlp", to: toolDst)
        try makeExecutable(toolDst)

        return toolDst.path
    }

    private func copyResource(_ name: String, to destination: URL) throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: destination.path) {
            if fm.isExecutableFile(atPath: destination.path) {
                return
            }
            try? fm.removeItem(at: destination)
        }

        guard let sourceURL = Bundle.main.url(forResource: name, withExtension: nil) ??
              Bundle.main.resourceURL?.appendingPathComponent(name),
              fm.fileExists(atPath: sourceURL.path) else {
            throw YtDlpError.notFound
        }

        try fm.copyItem(at: sourceURL, to: destination)
    }

    private func makeExecutable(_ url: URL) throws {
        let path = url.path
        let fm = FileManager.default

        var attributes = try fm.attributesOfItem(atPath: path)
        attributes[.posixPermissions] = NSNumber(value: 0o755)
        try fm.setAttributes(attributes, ofItemAtPath: path)

        if !fm.isExecutableFile(atPath: path) {
            chmod(path, 0o755)
        }
    }
}
