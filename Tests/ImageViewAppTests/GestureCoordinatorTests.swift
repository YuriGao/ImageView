import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class GestureCoordinatorTests: XCTestCase {
    func testPanThresholdTriggersNavigationOnlyPastThreshold() {
        let canvas = ImageCanvasView()
        let coordinator = GestureCoordinator(canvas: canvas)
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        coordinator.applyPan(translation: CGPoint(x: -79, y: 0), state: .ended)
        coordinator.applyPan(translation: CGPoint(x: 79, y: 0), state: .ended)
        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 0)

        coordinator.applyPan(translation: CGPoint(x: -81, y: 0), state: .ended)
        coordinator.applyPan(translation: CGPoint(x: 81, y: 0), state: .ended)
        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(previousCount, 1)
    }
}
