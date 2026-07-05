import XCTest
@testable import ClipHackKit

final class XPostTextTests: XCTestCase {

    // MARK: - Status-ID detection (accepts)

    func testDetectsCanonicalXStatusURL() {
        XCTAssertEqual(
            XPostText.statusID(from: "https://x.com/atrupar/status/2073253157933666426"),
            "2073253157933666426"
        )
    }

    func testDetectsTwitterDotComAndTrailingWhitespace() {
        XCTAssertEqual(XPostText.statusID(from: "  https://twitter.com/jack/status/20\n"), "20")
    }

    func testDetectsWWWAndQueryString() {
        XCTAssertEqual(XPostText.statusID(from: "https://www.x.com/foo/status/123?s=20&t=abc"), "123")
    }

    func testDetectsMobileHostAndPhotoSuffix() {
        XCTAssertEqual(XPostText.statusID(from: "https://mobile.twitter.com/foo/status/123/photo/1"), "123")
    }

    func testDetectsIWebStatusForm() {
        XCTAssertEqual(XPostText.statusID(from: "https://x.com/i/web/status/456"), "456")
    }

    // MARK: - Status-ID detection (rejects)

    func testRejectsProfileMediaSearchAndHomePaths() {
        XCTAssertNil(XPostText.statusID(from: "https://x.com/atrupar"))
        XCTAssertNil(XPostText.statusID(from: "https://x.com/home"))
        XCTAssertNil(XPostText.statusID(from: "https://x.com/search?q=foo"))
        XCTAssertNil(XPostText.statusID(from: "https://x.com/atrupar/media"))
    }

    func testRejectsNonXHosts() {
        XCTAssertNil(XPostText.statusID(from: "https://www.youtube.com/watch?v=abc"))
        XCTAssertNil(XPostText.statusID(from: "https://notx.com/foo/status/123"))
        XCTAssertNil(XPostText.statusID(from: "https://x.com.evil.com/foo/status/123"))
    }

    func testRejectsMalformedStatusIDs() {
        XCTAssertNil(XPostText.statusID(from: "https://x.com/foo/status/abc"))
        XCTAssertNil(XPostText.statusID(from: "https://x.com/foo/status/"))
        XCTAssertNil(XPostText.statusID(from: "not a url at all"))
    }

    // MARK: - Token & endpoint

    func testTokenIsNonEmptyBase36() {
        let token = XPostText.token(forID: "2073253157933666426")
        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(token.allSatisfy { ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "z") })
        XCTAssertFalse(token.contains("0"), "widget token strips zeros")
    }

    func testSyndicationURLCarriesIDAndToken() {
        let url = XPostText.syndicationURL(forID: "20")
        let comps = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(comps?.host, "cdn.syndication.twimg.com")
        XCTAssertEqual(comps?.path, "/tweet-result")
        XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "id" })?.value, "20")
        XCTAssertNotNil(comps?.queryItems?.first(where: { $0.name == "token" })?.value)
    }

    // MARK: - Trimming to display_text_range

    func testTrimStripsTrailingMediaLinkViaRange() {
        // Real atrupar payload shape: text + trailing t.co, visible range [0,101].
        let text = "Trump traveled all the way to South Dakota to read a half-baked red scare speech straight out of 1950 https://t.co/FIu6O5fEf1"
        let result = XPostText.trimmedText(text, displayTextRange: [0, 101])
        XCTAssertFalse(result.contains("t.co"))
        XCTAssertTrue(result.hasPrefix("Trump traveled"))
        XCTAssertTrue(result.hasSuffix("1950"))
    }

    func testTrimFallsBackToFullTextWhenRangeAbsentOrOutOfBounds() {
        XCTAssertEqual(XPostText.trimmedText("hello world", displayTextRange: nil), "hello world")
        XCTAssertEqual(XPostText.trimmedText("hello", displayTextRange: [0, 999]), "hello")
        XCTAssertEqual(XPostText.trimmedText("hello", displayTextRange: [3]), "hello")
    }

    // MARK: - JSON parsing (fixtures mirror real responses)

    func testParsesRealAtruparFixture() {
        let json = Data("""
        {"text":"Trump traveled all the way to South Dakota to read a half-baked red scare speech straight out of 1950 https://t.co/FIu6O5fEf1","display_text_range":[0,101]}
        """.utf8)
        let result = XPostText.parsePostText(fromJSON: json)
        XCTAssertEqual(result, "Trump traveled all the way to South Dakota to read a half-baked red scare speech straight out of 1950")
    }

    func testParsesRealJackFixture() {
        let json = Data("""
        {"text":"just setting up my twttr","display_text_range":[0,24]}
        """.utf8)
        XCTAssertEqual(XPostText.parsePostText(fromJSON: json), "just setting up my twttr")
    }

    func testParseReturnsNilForHTMLErrorBody() {
        // A bad ID makes the endpoint return an HTML page, not JSON.
        let html = Data("<!DOCTYPE html><html><head></head><body>not found</body></html>".utf8)
        XCTAssertNil(XPostText.parsePostText(fromJSON: html))
    }

    func testParseReturnsNilWhenTextMissingOrEmpty() {
        XCTAssertNil(XPostText.parsePostText(fromJSON: Data(#"{"display_text_range":[0,5]}"#.utf8)))
        XCTAssertNil(XPostText.parsePostText(fromJSON: Data(#"{"text":"   ","display_text_range":[0,3]}"#.utf8)))
    }
}
