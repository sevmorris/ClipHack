import XCTest
@testable import ClipHackKit

final class ClipRecordTests: XCTestCase {

    func testTimestampShapes() {
        for good in ["1:13 to :55", ":30 to :12", "To :17", "0:05", "1:13-2:00", "to 1:02",
                     "0:05 to end", ":18 to end"] {
            XCTAssertTrue(ClipRecord.isTimestamp(good), good)
        }
        for bad in ["Trump — said it", "second para", "100", "AUDIENCE: 😬", ""] {
            XCTAssertFalse(ClipRecord.isTimestamp(bad), bad)
        }
    }

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
