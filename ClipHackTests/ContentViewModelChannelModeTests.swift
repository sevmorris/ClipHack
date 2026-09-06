import XCTest
@testable import ClipHackKit

/// Setting and reading a clip's channel override from the row menu.
@MainActor
final class ContentViewModelChannelModeTests: XCTestCase {

    private func makeViewModel(count: Int) -> ContentViewModel {
        let vm = ContentViewModel()
        vm.files = (0..<count).map { FileItem(url: URL(fileURLWithPath: "/tmp/clips/\($0).wav")) }
        return vm
    }

    func testDefaultsToFollowingTheSettingsPanel() {
        let vm = makeViewModel(count: 1)
        XCTAssertNil(vm.files[0].channelMode)
    }

    func testSetsTheModeOnEverySelectedRowAndLeavesOthersAlone() {
        let vm = makeViewModel(count: 3)
        vm.setChannelMode(.monoRight, for: [vm.files[0].id, vm.files[2].id])

        XCTAssertEqual(vm.files[0].channelMode, .monoRight)
        XCTAssertNil(vm.files[1].channelMode, "an unselected row is untouched")
        XCTAssertEqual(vm.files[2].channelMode, .monoRight)
    }

    func testClearingReturnsARowToTheSettingsPanel() {
        let vm = makeViewModel(count: 1)
        vm.setChannelMode(.stereo, for: [vm.files[0].id])
        vm.setChannelMode(nil, for: [vm.files[0].id])
        XCTAssertNil(vm.files[0].channelMode)
    }

    func testAnEmptySelectionChangesNothing() {
        let vm = makeViewModel(count: 1)
        vm.setChannelMode(.stereo, for: [])
        XCTAssertNil(vm.files[0].channelMode)
    }

    func testAnUnknownIDChangesNothing() {
        let vm = makeViewModel(count: 1)
        vm.setChannelMode(.stereo, for: [UUID()])
        XCTAssertNil(vm.files[0].channelMode)
    }

    // MARK: - What the menu shows a checkmark against

    func testCommonModeIsTheSharedOneOrNilWhenRowsDisagree() {
        let vm = makeViewModel(count: 2)
        let ids = Set(vm.files.map(\.id))

        XCTAssertNil(vm.commonChannelMode(for: ids), "all following the panel")

        vm.setChannelMode(.monoLeft, for: ids)
        XCTAssertEqual(vm.commonChannelMode(for: ids), .monoLeft)

        vm.setChannelMode(.stereo, for: [vm.files[1].id])
        XCTAssertNil(vm.commonChannelMode(for: ids), "a mixed selection claims no mode")
    }
}
