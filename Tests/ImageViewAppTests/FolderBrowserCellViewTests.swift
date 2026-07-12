import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class FolderBrowserCellViewTests: XCTestCase {
    func testSelectionChangesAppearanceWithoutChangingLayout() {
        let cell = FolderBrowserCellView()
        cell.loadView()
        let size = cell.view.fittingSize

        cell.isSelected = true
        XCTAssertTrue(cell.testingShowsSelection)
        XCTAssertEqual(cell.view.fittingSize, size)

        cell.isSelected = false
        XCTAssertFalse(cell.testingShowsSelection)
    }
}
