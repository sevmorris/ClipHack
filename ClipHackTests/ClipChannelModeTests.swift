import XCTest
@testable import ClipHackKit

/// The precedence rule between a clip's own channel setting and the panel's.
final class ClipChannelModeTests: XCTestCase {

    private func settings(
        stereo: Bool,
        channel: ClipHackSettings.MonoChannel
    ) -> ClipHackSettings {
        var s = ClipHackSettings()
        s.stereoOutput = stereo
        s.channel = channel
        return s
    }

    // MARK: - No override

    func testNilFollowsThePanel() {
        let mono = ClipChannelMode.resolve(nil, settings: settings(stereo: false, channel: .right))
        XCTAssertFalse(mono.stereo)
        XCTAssertEqual(mono.channel, .right)

        let stereo = ClipChannelMode.resolve(nil, settings: settings(stereo: true, channel: .left))
        XCTAssertTrue(stereo.stereo)
    }

    // MARK: - Override wins

    func testOverrideBeatsThePanelInBothDirections() {
        // Panel says stereo; this clip says mono left.
        let forcedMono = ClipChannelMode.resolve(.monoLeft, settings: settings(stereo: true, channel: .right))
        XCTAssertFalse(forcedMono.stereo, "the clip's own setting wins")
        XCTAssertEqual(forcedMono.channel, .left, "and brings its own channel, not the panel's")

        // Panel says mono left; this clip says stereo.
        let forcedStereo = ClipChannelMode.resolve(.stereo, settings: settings(stereo: false, channel: .left))
        XCTAssertTrue(forcedStereo.stereo)
    }

    func testMonoRightPicksTheRightChannel() {
        let r = ClipChannelMode.resolve(.monoRight, settings: settings(stereo: false, channel: .left))
        XCTAssertFalse(r.stereo)
        XCTAssertEqual(r.channel, .right)
    }

    /// A clip set back to Follow Settings must land on whatever the panel says
    /// now — so .stereo must not quietly rewrite the panel's channel on its way
    /// through.
    func testStereoOverrideLeavesThePanelChannelIntact() {
        let s = settings(stereo: false, channel: .right)
        XCTAssertEqual(ClipChannelMode.resolve(.stereo, settings: s).channel, .right)
        XCTAssertEqual(ClipChannelMode.resolve(nil, settings: s).channel, .right)
    }

    // MARK: - Labels

    func testEveryModeHasDistinctWording() {
        let labels = ClipChannelMode.allCases.map(\.label)
        let badges = ClipChannelMode.allCases.map(\.badge)
        XCTAssertEqual(Set(labels).count, ClipChannelMode.allCases.count)
        XCTAssertEqual(Set(badges).count, ClipChannelMode.allCases.count)
        XCTAssertFalse(labels.contains { $0.isEmpty })
    }
}
