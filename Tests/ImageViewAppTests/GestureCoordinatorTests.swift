import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class GestureCoordinatorTests: XCTestCase {
    func testTwoFingerTapTogglesFitAndActualSize() {
        let canvas = ImageCanvasView()
        let coordinator = GestureCoordinator(canvas: canvas)

        coordinator.applyTwoFingerTap()
        XCTAssertEqual(canvas.scale, 2, accuracy: 0.001)

        coordinator.applyTwoFingerTap()
        XCTAssertEqual(canvas.scale, 1, accuracy: 0.001)
    }
}
