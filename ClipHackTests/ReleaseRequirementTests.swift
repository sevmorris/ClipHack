import XCTest
@testable import ClipHackKit

/// `minimumMacOS(inReleaseNotes:)` and its helpers decide whether the update
/// check offers a release, from the marker release.sh writes into its notes.
/// A missing or malformed marker sets no minimum, so the release is offered as
/// it always was.
final class ReleaseRequirementTests: XCTestCase {

    private func version(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    private func fields(_ version: OperatingSystemVersion?) -> [Int]? {
        version.map { [$0.majorVersion, $0.minorVersion, $0.patchVersion] }
    }

    /// The footer release.sh appends after the curated notes.
    func testReadsTheMarkerReleaseShWrites() {
        XCTAssertEqual(fields(ReleaseRequirement.minimumMacOS(inReleaseNotes: "**Fixed**\n- Something.\n\n---\nRequires macOS 15.0 or later.\n<!-- minimum-macos: 15.0 -->")), [15, 0, 0])
        XCTAssertEqual(fields(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15.2.1 -->")), [15, 2, 1])
        XCTAssertEqual(fields(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 26 -->")), [26, 0, 0])
    }

    /// A release from before the marker runs on every macOS the installed build
    /// does, and the visible "Requires macOS" line is prose, not the marker.
    func testNotesWithoutAMarkerSetNoMinimum() {
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: nil))
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "**Fixed**\n- Something."))
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "Requires macOS 15.0 or later."))
    }

    func testAMalformedMarkerSetsNoMinimum() {
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: fifteen -->"))
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15.0"))
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 15..0 -->"))
        XCTAssertNil(ReleaseRequirement.minimumMacOS(inReleaseNotes: "<!-- minimum-macos: 1.2.3.4 -->"))
    }

    func testComparesMajorThenMinorThenPatch() {
        XCTAssertFalse(ReleaseRequirement.runs(on: version(14, 6), given: version(15)))
        XCTAssertTrue(ReleaseRequirement.runs(on: version(15), given: version(15)))
        XCTAssertTrue(ReleaseRequirement.runs(on: version(26, 7, 1), given: version(15)))
        XCTAssertFalse(ReleaseRequirement.runs(on: version(15), given: version(15, 1)))
        XCTAssertTrue(ReleaseRequirement.runs(on: version(15, 1), given: version(15, 0, 1)))
    }

    func testDescribesAVersionTheWayMacOSDoes() {
        XCTAssertEqual(ReleaseRequirement.describe(version(15)), "15.0")
        XCTAssertEqual(ReleaseRequirement.describe(version(15, 2, 1)), "15.2.1")
    }
}
