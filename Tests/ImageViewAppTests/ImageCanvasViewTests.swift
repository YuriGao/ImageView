import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class ImageCanvasViewTests: XCTestCase {
    func testTransformHelpersUpdateScaleAndOffset() {
        let canvas = ImageCanvasView()

        canvas.zoom(by: 2.0, around: CGPoint(x: 20, y: 10))
        canvas.pan(by: CGPoint(x: 6, y: -4))

        XCTAssertEqual(canvas.scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.x, -14, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, -14, accuracy: 0.001)

        canvas.resetViewTransform()

        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset, .zero)
    }

    func testToggleFitOrActualSizeSwitchesBetweenZoomedAndFit() {
        let canvas = ImageCanvasView()

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 2.0, accuracy: 0.001)

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset, .zero)
    }

    func testScrollPansWhenZoomed() {
        let canvas = ImageCanvasView()
        canvas.scale = 2.0

        canvas.handleScroll(deltaX: 8, deltaY: -12, at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(canvas.offset.x, -8, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 12, accuracy: 0.001)
    }

    func testScrollZoomsWhenUsingZoomModifier() {
        let canvas = ImageCanvasView()
        canvas.scale = 2.0

        canvas.handleScroll(deltaX: 0, deltaY: -10, at: CGPoint(x: 40, y: 30), modifierFlags: [.option])

        XCTAssertGreaterThan(canvas.scale, 2.0)
    }

    func testHorizontalScrollNavigatesWhenFitToWindow() {
        let canvas = ImageCanvasView()
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(deltaX: -25, deltaY: 2, at: .zero)
        canvas.handleScroll(deltaX: 25, deltaY: 2, at: .zero)

        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(previousCount, 1)
    }

    func testMouseDragPansOnlyWhenZoomed() {
        let canvas = ImageCanvasView()

        canvas.beginMouseDrag(at: CGPoint(x: 10, y: 10))
        canvas.continueMouseDrag(to: CGPoint(x: 30, y: 20))
        XCTAssertEqual(canvas.offset, .zero)

        canvas.scale = 2.0
        canvas.beginMouseDrag(at: CGPoint(x: 10, y: 10))
        canvas.continueMouseDrag(to: CGPoint(x: 30, y: 20))
        canvas.endMouseDrag()

        XCTAssertEqual(canvas.offset.x, 20, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 10, accuracy: 0.001)
    }
}
