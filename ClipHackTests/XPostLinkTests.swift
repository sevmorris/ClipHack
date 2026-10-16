import XCTest
@testable import ClipHackKit

final class XPostLinkTests: XCTestCase {

    // MARK: - Status-ID detection (accepts)

    func testDetectsCanonicalXStatusURL() {
        XCTAssertEqual(
            XPostLink.statusID(from: "https://x.com/atrupar/status/2073253157933666426"),
            "2073253157933666426"
        )
    }

    func testDetectsTwitterDotComAndTrailingWhitespace() {
        XCTAssertEqual(XPostLink.statusID(from: "  https://twitter.com/jack/status/20\n"), "20")
    }

    func testDetectsWWWAndQueryString() {
        XCTAssertEqual(XPostLink.statusID(from: "https://www.x.com/foo/status/123?s=20&t=abc"), "123")
    }

    func testDetectsMobileHostAndPhotoSuffix() {
        XCTAssertEqual(XPostLink.statusID(from: "https://mobile.twitter.com/foo/status/123/photo/1"), "123")
    }

    func testDetectsIWebStatusForm() {
        XCTAssertEqual(XPostLink.statusID(from: "https://x.com/i/web/status/456"), "456")
    }

    // MARK: - Status-ID detection (rejects)

    func testRejectsProfileMediaSearchAndHomePaths() {
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/atrupar"))
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/home"))
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/search?q=foo"))
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/atrupar/media"))
    }

    func testRejectsNonXHosts() {
        XCTAssertNil(XPostLink.statusID(from: "https://www.youtube.com/watch?v=abc"))
        XCTAssertNil(XPostLink.statusID(from: "https://notx.com/foo/status/123"))
        XCTAssertNil(XPostLink.statusID(from: "https://x.com.evil.com/foo/status/123"))
    }

    func testRejectsMalformedStatusIDs() {
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/foo/status/abc"))
        XCTAssertNil(XPostLink.statusID(from: "https://x.com/foo/status/"))
        XCTAssertNil(XPostLink.statusID(from: "not a url at all"))
    }
}
