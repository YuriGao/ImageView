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

    func testAppearanceChangesRefreshHoverAndPressedWithoutChangingSize() throws {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        let size = button.frame.size
        button.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        button.setHoveredForTesting(true)
        let hoverRefreshCount = button.testingAppearanceRefreshCount

        button.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertGreaterThan(button.testingAppearanceRefreshCount, hoverRefreshCount)
        XCTAssertTrue(button.testingShowsHover)
        XCTAssertEqual(
            try XCTUnwrap(button.layer?.backgroundColor?.alpha),
            CGFloat(0.12),
            accuracy: 0.001
        )
        XCTAssertEqual(button.frame.size, size)

        button.highlight(true)
        let pressedRefreshCount = button.testingAppearanceRefreshCount
        button.appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        XCTAssertGreaterThan(button.testingAppearanceRefreshCount, pressedRefreshCount)
        XCTAssertTrue(button.testingShowsPressed)
        XCTAssertEqual(
            try XCTUnwrap(button.layer?.backgroundColor?.alpha),
            CGFloat(0.20),
            accuracy: 0.001
        )
        XCTAssertEqual(button.frame.size, size)
    }

    func testFocusRingMaskDrawsOpaqueGeometryInsideMaskBounds() throws {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        button.setFocusedForTesting(true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 24,
            pixelsHigh: 24,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.current = previousContext }

        NSColor.black.setFill()
        button.drawFocusRingMask()
        context.flushGraphics()

        XCTAssertEqual(button.focusRingMaskBounds, button.bounds)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 12, y: 12)).alphaComponent, 0.9)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
    }

    func testRepeatedMouseClickIsIgnored() {
        XCTAssertTrue(HoverToolbarButton.acceptsMouseClick(clickCount: 1))
        XCTAssertFalse(HoverToolbarButton.acceptsMouseClick(clickCount: 2))
        XCTAssertFalse(HoverToolbarButton.acceptsMouseClick(clickCount: 3))
    }
}
