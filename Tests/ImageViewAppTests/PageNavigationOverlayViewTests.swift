import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class PageNavigationOverlayViewTests: XCTestCase {
    func testControlsUseApprovedSymbolsAndDimensions() {
        let view = PageNavigationOverlayView()

        XCTAssertEqual(PageNavigationOverlayView.controlSize, CGSize(width: 44, height: 64))
        XCTAssertEqual(view.debugPreviousButton.image?.accessibilityDescription, AppStrings.text("menu.view.previousImage"))
        XCTAssertEqual(view.debugNextButton.image?.accessibilityDescription, AppStrings.text("menu.view.nextImage"))
    }

    func testUpdateAppliesSequenceBoundaryStates() {
        let view = PageNavigationOverlayView()

        view.update(previousEnabled: false, nextEnabled: true)

        XCTAssertFalse(view.debugPreviousButton.isEnabled)
        XCTAssertTrue(view.debugNextButton.isEnabled)
    }

    func testButtonsCallNavigationCallbacks() {
        let view = PageNavigationOverlayView()
        var previousCount = 0
        var nextCount = 0
        view.onPrevious = { previousCount += 1 }
        view.onNext = { nextCount += 1 }

        view.performDebugPrevious()
        view.performDebugNext()

        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(nextCount, 1)
    }

    func testOverlayUsesAppearanceAdaptiveBorderAndBackground() {
        XCTAssertEqual(PageNavigationOverlayView.backgroundColor, .windowBackgroundColor)
        XCTAssertEqual(PageNavigationOverlayView.borderColor, .separatorColor)
        XCTAssertEqual(PageNavigationOverlayView.borderWidth(forBackingScaleFactor: 2), 0.5)
    }
}
