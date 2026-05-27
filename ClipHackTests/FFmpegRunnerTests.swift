import XCTest
@testable import ClipHack

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
}
