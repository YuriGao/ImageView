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
}
