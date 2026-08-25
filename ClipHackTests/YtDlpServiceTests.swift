import XCTest
@testable import ClipHackKit

final class YtDlpServiceTests: XCTestCase {

    private func args(
        url: String = "https://example.com/watch?v=abc123",
        destination: String = "/Users/test/Music/ClipHack",
        ffmpegDirectory: String = "/Applications/ClipHack.app/Contents/Resources",
        customStem: String? = nil
    ) -> [String] {
        YtDlpService.buildArguments(
            url: url,
            destination: destination,
            ffmpegDirectory: ffmpegDirectory,
            customStem: customStem
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // MARK: - Download directory resolution

    func testResolveDownloadDirectoryNilFallsBackToDefault() {
        XCTAssertEqual(YtDlpService.resolveDownloadDirectory(nil), YtDlpService.downloadDirectory)
    }

    func testResolveDownloadDirectoryEmptyFallsBackToDefault() {
        XCTAssertEqual(YtDlpService.resolveDownloadDirectory(""), YtDlpService.downloadDirectory)
    }

    func testResolveDownloadDirectoryUsesCustomPath() {
        let resolved = YtDlpService.resolveDownloadDirectory("/tmp/cliphack-dest")
        XCTAssertEqual(resolved.path, "/tmp/cliphack-dest")
        XCTAssertNotEqual(resolved, YtDlpService.downloadDirectory)
    }

    // MARK: - Missing / writable download directory

    func testCustomDownloadDirectoryMissingIsFalseForNilOrEmpty() {
        XCTAssertFalse(YtDlpService.customDownloadDirectoryMissing(nil))
        XCTAssertFalse(YtDlpService.customDownloadDirectoryMissing(""))
    }

    func testCustomDownloadDirectoryMissingIsFalseForExistingDir() {
        XCTAssertFalse(YtDlpService.customDownloadDirectoryMissing(FileManager.default.temporaryDirectory.path))
    }

    func testCustomDownloadDirectoryMissingIsTrueForAbsentPath() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-absent-\(UUID().uuidString)")
        XCTAssertTrue(YtDlpService.customDownloadDirectoryMissing(absent.path))
    }

    func testCustomDownloadDirectoryMissingIsTrueForFilePath() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-file-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(YtDlpService.customDownloadDirectoryMissing(file.path),
                      "a regular file is not a usable directory")
    }

    func testPrepareWritableDirectoryCreatesAndSucceeds() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-prep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(YtDlpService.prepareWritableDirectory(dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testPrepareWritableDirectoryFailsWhenParentIsAFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-parent-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // A subdirectory can't be created under a regular file.
        XCTAssertFalse(YtDlpService.prepareWritableDirectory(file.appendingPathComponent("sub")))
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

    // MARK: - Custom stem in the output template

    func testCustomStemReplacesTitleTemplate() {
        let arguments = args(customStem: "My Custom Clip")
        XCTAssertEqual(value(after: "-o", in: arguments), "My Custom Clip.%(ext)s")
    }

    func testCustomStemEscapesPercentForTemplateSyntax() {
        let arguments = args(customStem: "50% off deal")
        XCTAssertEqual(value(after: "-o", in: arguments), "50%% off deal.%(ext)s")
    }

    func testNoCustomStemKeepsDefaultTitleTemplate() {
        XCTAssertEqual(value(after: "-o", in: args()), "%(title)s.%(ext)s")
    }

    // MARK: - Stem sanitization

    func testSanitizedStemTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(YtDlpService.sanitizedStem("  My   Clip \n Two  "), "My Clip Two")
    }

    func testSanitizedStemReplacesPathAndFinderSeparators() {
        XCTAssertEqual(YtDlpService.sanitizedStem("AC/DC: Live"), "AC-DC- Live")
    }

    func testSanitizedStemKeepsPercentForFilesystem() {
        // "%" is legal in filenames; escaping happens only at template build.
        XCTAssertEqual(YtDlpService.sanitizedStem("50% off"), "50% off")
    }

    func testSanitizedStemStripsLeadingAndTrailingDots() {
        XCTAssertEqual(YtDlpService.sanitizedStem("..hidden name.."), "hidden name")
    }

    func testSanitizedStemBlankOrJunkReturnsNil() {
        XCTAssertNil(YtDlpService.sanitizedStem(""))
        XCTAssertNil(YtDlpService.sanitizedStem("   \n  "))
        XCTAssertNil(YtDlpService.sanitizedStem("..."))
        // Separator-only input maps mechanically, not to nil — "-" is legal.
        XCTAssertEqual(YtDlpService.sanitizedStem("/"), "-")
    }

    func testSanitizedStemCapsLengthAtCharacterBoundary() {
        let long = String(repeating: "é", count: 200) // 2 UTF-8 bytes each
        let stem = YtDlpService.sanitizedStem(long)
        XCTAssertNotNil(stem)
        XCTAssertLessThanOrEqual(stem!.utf8.count, 180)
        XCTAssertTrue(stem!.allSatisfy { $0 == "é" })
    }

    // MARK: - Stem uniquification

    func testUniqueStemKeepsFreeName() {
        XCTAssertEqual(YtDlpService.uniqueStem("clip") { _ in false }, "clip")
    }

    func testUniqueStemSuffixesTakenName() {
        let taken: Set<String> = ["clip"]
        XCTAssertEqual(YtDlpService.uniqueStem("clip") { taken.contains($0) }, "clip-2")
    }

    func testUniqueStemSkipsSequentialCollisions() {
        let taken: Set<String> = ["clip", "clip-2", "clip-3"]
        XCTAssertEqual(YtDlpService.uniqueStem("clip") { taken.contains($0) }, "clip-4")
    }

    // MARK: - Per-clip folders

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliphack-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
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
    // MARK: - A name already taken by a different clip

    func testASkippedDownloadIsRecognised() {
        // yt-dlp printed its "already downloaded" notice and no after_move
        // marker: nothing was fetched.
        XCTAssertTrue(YtDlpService.skippedBecauseNameTaken(
            markerPath: nil, alreadyDownloadedPath: "/dest/Title.m4a"
        ))
        XCTAssertTrue(YtDlpService.skippedBecauseNameTaken(
            markerPath: "", alreadyDownloadedPath: "/dest/Title.m4a"
        ))
    }

    func testARealDownloadIsNotASkip() {
        XCTAssertFalse(YtDlpService.skippedBecauseNameTaken(
            markerPath: "/dest/Title.m4a", alreadyDownloadedPath: nil
        ))
        XCTAssertFalse(YtDlpService.skippedBecauseNameTaken(
            markerPath: "/dest/Title.m4a", alreadyDownloadedPath: "/dest/Title.m4a"
        ), "the marker is authoritative when both are present")
        XCTAssertFalse(YtDlpService.skippedBecauseNameTaken(
            markerPath: nil, alreadyDownloadedPath: nil
        ))
    }

    func testTheNameTakenErrorSaysWhatToDo() {
        let message = YtDlpError.nameTaken("Title.m4a").errorDescription ?? ""
        XCTAssertTrue(message.contains("Title.m4a"))
        XCTAssertTrue(message.contains("custom name"))
    }
}
