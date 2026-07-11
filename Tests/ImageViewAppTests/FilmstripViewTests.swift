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

    func testMiddleSelectionIsCenteredInViewport() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 360, height: 78)

        filmstrip.apply(items: items, current: items[3])
        filmstrip.layoutSubtreeIfNeeded()

        assertSelectedThumbnailCentered(filmstrip)
    }

    func testFirstAndLastSelectionsUseEmptySpaceToRemainCentered() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 360, height: 78)

        filmstrip.apply(items: items, current: items.first)
        filmstrip.layoutSubtreeIfNeeded()
        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), 0)

        filmstrip.apply(items: items, current: items.last)
        filmstrip.layoutSubtreeIfNeeded()
        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugTrailingSpacerWidth(), 0)
    }

    func testViewportResizeRecomputesSpacersAndRecentersSelection() {
        let items = makeItems(count: 7)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 300, height: 78)
        filmstrip.apply(items: items, current: items[3])
        filmstrip.layoutSubtreeIfNeeded()
        let originalSpacerWidth = filmstrip.debugLeadingSpacerWidth()

        filmstrip.frame.size.width = 460
        filmstrip.layoutSubtreeIfNeeded()

        assertSelectedThumbnailCentered(filmstrip)
        XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), originalSpacerWidth)
    }

    func testNilOrMissingSelectionReturnsToLeadingPosition() {
        let items = makeItems(count: 5)
        let filmstrip = FilmstripView()
        filmstrip.frame = NSRect(x: 0, y: 0, width: 300, height: 78)
        filmstrip.apply(items: items, current: items[3])

        filmstrip.apply(items: items, current: nil)
        XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)

        let missing = ImageItem(url: URL(fileURLWithPath: "/tmp/missing.png"), format: .png)
        filmstrip.apply(items: items, current: missing)
        XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    private func makeItems(count: Int) -> [ImageItem] {
        (0..<count).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/\($0).png"), format: .png)
        }
    }

    private func assertSelectedThumbnailCentered(
        _ filmstrip: FilmstripView,
        accuracy: CGFloat = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let selectedCenter = filmstrip.debugSelectedCenterInViewport() else {
            XCTFail("Expected a selected thumbnail", file: file, line: line)
            return
        }
        XCTAssertEqual(
            selectedCenter,
            filmstrip.contentView.bounds.midX,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }
}
