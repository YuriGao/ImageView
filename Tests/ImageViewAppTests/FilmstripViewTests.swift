import Foundation
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FilmstripViewTests: XCTestCase {
    func testOverlayUsesSystemWindowBackgroundInsteadOfVisualEffectMaterial() {
        XCTAssertEqual(FilmstripOverlayView.backgroundColor, .windowBackgroundColor)
    }

    func testOverlayBorderMatchesSystemSeparatorAtOnePhysicalPixel() {
        XCTAssertEqual(FilmstripOverlayView.borderColor, .separatorColor)
        XCTAssertEqual(FilmstripOverlayView.borderWidth(forBackingScaleFactor: 1), 1)
        XCTAssertEqual(FilmstripOverlayView.borderWidth(forBackingScaleFactor: 2), 0.5)
    }

    func testSelectedThumbnailUsesLargerDimensionsThanRegularThumbnail() {
        let regularSize = FilmstripView.thumbnailSize(isSelected: false)
        let selectedSize = FilmstripView.thumbnailSize(isSelected: true)

        XCTAssertGreaterThan(selectedSize.width, regularSize.width)
        XCTAssertGreaterThan(selectedSize.height, regularSize.height)
    }

    func testFilmstripUsesReadableThumbnailAndOverlayDimensions() {
        XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: false), CGSize(width: 72, height: 64))
        XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: true), CGSize(width: 86, height: 76))
        XCTAssertEqual(FilmstripView.thumbnailDecodeMaxPixelSize, 192)
        XCTAssertEqual(MainWindowController.filmstripOverlayHeight, 98)
    }

    func testApplyBuildsButtonsAndSelectionCallsOnSelect() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/b.png"), format: .png)
        let filmstrip = FilmstripView()
        let expectation = expectation(description: "select")
        var selected: ImageItem?

        filmstrip.onSelect = { item in
            selected = item
            expectation.fulfill()
        }

        filmstrip.apply(items: [first, second], current: second)

        let buttons = filmstrip.debugButtons()
        XCTAssertEqual(buttons.map(\.title), ["a", "b"])
        XCTAssertFalse(buttons[0].isBordered)
        XCTAssertTrue(buttons[1].isBordered)
        XCTAssertEqual(buttons[1].imagePosition, .imageOnly)

        filmstrip.performDebugSelection(buttons[0])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(selected?.url, first.url)
        XCTAssertEqual(selected?.format, .png)
    }
}
