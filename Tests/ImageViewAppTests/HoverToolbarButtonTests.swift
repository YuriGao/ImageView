import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class HoverToolbarButtonTests: XCTestCase {
    func testHoverAndPressChangeAppearanceWithoutChangingSize() {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        let size = button.frame.size

        button.setHoveredForTesting(true)
        XCTAssertTrue(button.testingShowsHover)
        XCTAssertEqual(button.frame.size, size)

        button.highlight(true)
        XCTAssertTrue(button.testingShowsPressed)
        XCTAssertEqual(button.frame.size, size)
    }

    func testDisabledButtonDoesNotShowHover() {
        let button = HoverToolbarButton()
        button.isEnabled = false
        button.setHoveredForTesting(true)
        XCTAssertFalse(button.testingShowsHover)
    }

    func testKeyboardFocusUsesFocusRingWithoutChangingSize() {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        button.setFocusedForTesting(true)
        XCTAssertTrue(button.testingShowsFocus)
        XCTAssertEqual(button.frame.size, NSSize(width: 24, height: 24))
    }
}
