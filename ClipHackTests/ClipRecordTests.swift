import XCTest
@testable import ClipHackKit

final class ClipRecordTests: XCTestCase {

    func testTheSameXPostIsTheSameSourceWhateverItsQuery() {
        XCTAssertTrue(ClipRecord.isSameSource(
            "https://x.com/acyn/status/2109406640567161167?s=43",
            "https://twitter.com/acyn/status/2109406640567161167"
        ))
        XCTAssertFalse(ClipRecord.isSameSource(
            "https://www.youtube.com/watch?v=a", "https://www.youtube.com/watch?v=b"
        ), "a YouTube video's id is in its query")
        XCTAssertFalse(ClipRecord.isSameSource("", ""), "two clips with no link are not one clip")
    }
}
