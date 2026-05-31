import XCTest
@testable import ClipHack

final class ClipHackOutputNamingTests: XCTestCase {

    func testLooksLikeClipHackOutputDetectsClippedSuffix() {
        let url = URL(fileURLWithPath: "/tmp/news-44kclipped-1dB.wav")
        XCTAssertTrue(ClipHackOutputNaming.looksLikeClipHackOutput(url))
    }

    func testLooksLikeClipHackOutputDetectsNormClippedSuffix() {
        let url = URL(fileURLWithPath: "/tmp/clip-48knorm-clipped-3dB.wav")
        XCTAssertTrue(ClipHackOutputNaming.looksLikeClipHackOutput(url))
    }

    func testLooksLikeClipHackOutputRejectsRawSource() {
        let url = URL(fileURLWithPath: "/tmp/broadcast_clip.wav")
        XCTAssertFalse(ClipHackOutputNaming.looksLikeClipHackOutput(url))
    }
}
