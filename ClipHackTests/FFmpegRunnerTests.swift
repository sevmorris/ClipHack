import XCTest
@testable import ClipHackKit

final class FFmpegRunnerTests: XCTestCase {

    func testParseLoudnormJSONExtractsStringValues() {
        let stderr = """
        [Parsed_loudnorm_0 @ 0x600003d14000] {
            "input_i" : "-23.50",
            "input_tp" : "-1.20",
            "input_lra" : "5.00",
            "input_thresh" : "-33.00",
            "target_offset" : "4.50"
        }
        """
        let dict = FFmpegRunner.parseLoudnormJSON(from: stderr)
        XCTAssertEqual(dict?["input_i"], "-23.50")
        XCTAssertEqual(dict?["target_offset"], "4.50")
    }

    func testLoudnormMeasurementsAreFiniteRejectsInf() {
        let json = [
            "input_i": "-inf",
            "input_tp": "-1.2",
            "input_lra": "5.0",
            "input_thresh": "-33.0",
            "target_offset": "4.5"
        ]
        XCTAssertFalse(FFmpegRunner.loudnormMeasurementsAreFinite(json))
    }

    /// /etc/hosts exists but is not an executable binary, so process.run() throws
    /// and we land in the launch-failure branch. Pins two things that branch now
    /// guarantees: it surfaces a ProcessingError rather than crashing with
    /// NSInvalidArgumentException, and it disarms the watchdog so nothing calls
    /// terminate() on a process that never launched.
    func testRunThrowsProcessingErrorOnNonExecutablePath() async {
        let nonExe = "/etc/hosts"
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExe))
        do {
            try await FFmpegRunner.run(exe: nonExe, args: [])
            XCTFail("expected ProcessingError — run should throw on a non-executable path")
        } catch is ProcessingError {
            // expected
        } catch {
            XCTFail("expected ProcessingError but got \(type(of: error)): \(error)")
        }
    }
}
