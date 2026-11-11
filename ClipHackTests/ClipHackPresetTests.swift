import XCTest
@testable import ClipHackKit

/// The built-in presets, and what retiring "Normalize & Limit" in 1.33.1 must
/// not break.
@MainActor
final class ClipHackPresetTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try ScratchDefaults.install()
    }

    override func tearDown() {
        ScratchDefaults.uninstall()
        super.tearDown()
    }

    func testBuiltInPresetsAreTheThreeLeftInMenuOrder() {
        XCTAssertEqual(ClipHackPreset.builtIn.map(\.name),
                       ["Zoom 48 kHz", "Broadcast Conform", "Clean & Limit"])
        XCTAssertEqual(ClipHackPreset.builtIn.map(\.id.uuidString), [
            "00000000-0000-0000-0000-000000000004",
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
        ])
    }

    /// Its id stays retired, so nothing could ever resolve to a different
    /// preset under the old one's id.
    func testTheRetiredIDIsNotABuiltInAndResolvesToNothing() {
        let retired = ClipHackPreset.retiredNormalizeAndLimitID
        XCTAssertFalse(ClipHackPreset.builtIn.contains { $0.id == retired })

        let store = ClipHackPresetStore()
        store.selectedPresetID = retired
        XCTAssertNil(store.selectedPreset, "the picker shows Custom rather than a preset that is gone")
    }

    /// Broadcast Conform carries what the retired preset did, so nobody loses
    /// a setting with it.
    func testBroadcastConformCoversTheRetiredPresetsSettings() throws {
        let conform = try XCTUnwrap(ClipHackPreset.builtIn.first { $0.name == "Broadcast Conform" })
        let retiredSettings = ClipHackSettings(
            sampleRate: .s44100, limitDb: -1.0, hpfCutoff: .standard,
            loudnormEnabled: true, loudnormTarget: -18.0,
            stereoOutput: false, channel: .left, outputDirectoryPath: nil
        )
        XCTAssertEqual(conform.settings, retiredSettings)
    }

    /// Saved presets are the only presets persisted, each with its own id and
    /// a full copy of its settings, so they load unchanged — including one
    /// saved from the retired preset's settings.
    func testSavedPresetsLoadUnchanged() throws {
        let saved = ClipHackPreset(name: "My Normalize", settings: ClipHackPreset.builtIn[1].settings)
        ClipHackSettings.store.set(try JSONEncoder().encode([saved]), forKey: "ClipHackUserPresets")

        let store = ClipHackPresetStore()
        XCTAssertEqual(store.presets, [saved])
        XCTAssertEqual(store.allPresets.count, ClipHackPreset.builtIn.count + 1)
    }
}
