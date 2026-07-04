import XCTest
@testable import ClipHack

final class YtDlpServiceTests: XCTestCase {

    private func args(
        url: String = "https://example.com/watch?v=abc123",
        destination: String = "/Users/test/Music/ClipHack",
        ffmpegDirectory: String = "/Applications/ClipHack.app/Contents/Resources"
    ) -> [String] {
        YtDlpService.buildArguments(url: url, destination: destination, ffmpegDirectory: ffmpegDirectory)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // MARK: - Argument building

    func testArgumentsPreferNativeAudioOnlyStream() {
        XCTAssertEqual(value(after: "-f", in: args()), "ba/b")
    }

    func testVideoSourcesForceAudioExtractionWithoutTranscode() {
        let arguments = args()
        XCTAssertTrue(arguments.contains("-x"),
                      "-x must be present so video-only sources get audio extracted")
        XCTAssertFalse(arguments.contains("--audio-format"),
                       "no --audio-format: native codec is kept, no re-encode")
    }

    func testArgumentsPointFFmpegLocationAtBundledDirectory() {
        let arguments = args(ffmpegDirectory: "/bundle/Contents/Resources")
        XCTAssertEqual(value(after: "--ffmpeg-location", in: arguments), "/bundle/Contents/Resources")
    }

    func testArgumentsSetDestinationAndEndWithURL() {
        let arguments = args(url: "https://youtu.be/xyz", destination: "/dest/dir")
        XCTAssertEqual(value(after: "-P", in: arguments), "/dest/dir")
        XCTAssertEqual(arguments.last, "https://youtu.be/xyz")
        XCTAssertTrue(arguments.contains("--no-playlist"))
        XCTAssertTrue(arguments.contains("--restrict-filenames"))
    }

    func testArgumentsRequestAfterMoveFilepathPrint() {
        let arguments = args()
        XCTAssertEqual(
            value(after: "--print", in: arguments),
            "after_move:\(YtDlpService.filepathMarker)%(filepath)s"
        )
    }

    func testArgumentsKeepProgressVisibleDespitePrintImplyingQuiet() {
        XCTAssertTrue(args().contains("--no-quiet"),
                      "--print implies quiet; without --no-quiet no progress or skip notice is emitted")
    }

    func testArgumentsUseVersionedRemoteComponentsSyntax() {
        // Bare "ejs" is rejected by the pinned 2026.06.09 binary.
        XCTAssertEqual(value(after: "--remote-components", in: args()), "ejs:github")
    }

    // MARK: - Already-downloaded notice parsing

    func testAlreadyDownloadedNoticeParsesPath() {
        let line = "[download] /Users/test/Music/ClipHack/Some_Title.m4a has already been downloaded"
        XCTAssertEqual(
            YtDlpService.alreadyDownloadedPath(fromLine: line),
            "/Users/test/Music/ClipHack/Some_Title.m4a"
        )
    }

    func testUnrelatedLinesDoNotParseAsAlreadyDownloaded() {
        XCTAssertNil(YtDlpService.alreadyDownloadedPath(fromLine: "[download]  42.0% of 3.40MiB at 1.20MiB/s"))
        XCTAssertNil(YtDlpService.alreadyDownloadedPath(fromLine: "[ExtractAudio] Destination: Title.m4a"))
        XCTAssertNil(YtDlpService.alreadyDownloadedPath(fromLine: "has already been downloaded"))
        XCTAssertNil(YtDlpService.alreadyDownloadedPath(fromLine: "[download] has already been downloaded"))
    }

    // MARK: - Downloaded-file resolution (the nil-filepath gap)

    func testMarkerPathIsAuthoritative() {
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: "/dest/final.opus",
            alreadyDownloadedPath: "/dest/stale.m4a",
            destination: "/dest"
        ) { _ in true }
        XCTAssertEqual(resolved, "/dest/final.opus")
    }

    func testAlreadyDownloadedAbsolutePathResolvesWhenFileExists() {
        var checked: [String] = []
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: nil,
            alreadyDownloadedPath: "/dest/Title.m4a",
            destination: "/dest"
        ) { path in
            checked.append(path)
            return true
        }
        XCTAssertEqual(resolved, "/dest/Title.m4a")
        XCTAssertEqual(checked, ["/dest/Title.m4a"], "existence must actually be verified on disk")
    }

    func testAlreadyDownloadedRelativePathResolvesAgainstDestination() {
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: nil,
            alreadyDownloadedPath: "Title.m4a",
            destination: "/dest/dir"
        ) { $0 == "/dest/dir/Title.m4a" }
        XCTAssertEqual(resolved, "/dest/dir/Title.m4a")
    }

    func testAlreadyDownloadedPathMissingOnDiskResolvesToNil() {
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: nil,
            alreadyDownloadedPath: "/dest/gone.m4a",
            destination: "/dest"
        ) { _ in false }
        XCTAssertNil(resolved)
    }

    func testNothingCapturedResolvesToNil() {
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: nil,
            alreadyDownloadedPath: nil,
            destination: "/dest"
        ) { _ in true }
        XCTAssertNil(resolved)
    }

    func testEmptyMarkerFallsBackToAlreadyDownloadedPath() {
        let resolved = YtDlpService.resolveDownloadedFile(
            markerPath: "",
            alreadyDownloadedPath: "/dest/Title.m4a",
            destination: "/dest"
        ) { _ in true }
        XCTAssertEqual(resolved, "/dest/Title.m4a")
    }
}
