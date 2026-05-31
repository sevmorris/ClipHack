import XCTest
@testable import ClipHack

final class FFmpegFiltersTests: XCTestCase {

    func testAresampleIncludesQualityFilter() {
        let filter = FFmpegFilters.aresample(to: 48000)
        XCTAssertTrue(filter.contains("filter_size=512"))
        XCTAssertTrue(filter.contains("48000"))
    }

    func testAresampleWithDitherIncludesTriangularHP() {
        let filter = FFmpegFilters.aresampleWithDither(to: 44100)
        XCTAssertTrue(filter.contains("dither_method=triangular_hp"))
    }

    func testLimiterCeilingAmplitudeAtMinus1dB() {
        XCTAssertEqual(FFmpegFilters.limiterCeilingAmplitude(dBFS: -1.0), "0.891251")
    }
}
