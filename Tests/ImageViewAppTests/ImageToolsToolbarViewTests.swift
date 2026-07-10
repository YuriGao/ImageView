import XCTest
@testable import ImageViewApp

final class ImageToolsToolbarViewTests: XCTestCase {
    func testToolbarStateReflectsDirectoryBoundsAndImageAvailability() {
        let first = ImageToolsToolbarState.state(hasImage: true, position: 0, itemCount: 3, isCropping: false)
        XCTAssertFalse(first.canShowPrevious)
        XCTAssertTrue(first.canShowNext)
        XCTAssertTrue(first.canEdit)
        XCTAssertTrue(first.canMoveToTrash)
        XCTAssertTrue(first.isVisible)

        let last = ImageToolsToolbarState.state(hasImage: true, position: 2, itemCount: 3, isCropping: false)
        XCTAssertTrue(last.canShowPrevious)
        XCTAssertFalse(last.canShowNext)

        let empty = ImageToolsToolbarState.state(hasImage: false, position: nil, itemCount: 0, isCropping: false)
        XCTAssertFalse(empty.canShowPrevious)
        XCTAssertFalse(empty.canShowNext)
        XCTAssertFalse(empty.canEdit)
        XCTAssertFalse(empty.canMoveToTrash)
    }

    func testToolbarStateHidesDuringCropping() {
        let state = ImageToolsToolbarState.state(hasImage: true, position: 1, itemCount: 3, isCropping: true)

        XCTAssertFalse(state.isVisible)
    }
}
