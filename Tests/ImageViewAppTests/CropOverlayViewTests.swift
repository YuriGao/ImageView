import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class CropOverlayViewTests: XCTestCase {
    func testBeginCroppingCreatesCenteredEightyPercentCrop() {
        let overlay = CropOverlayView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))

        overlay.beginCropping(in: CGRect(x: 50, y: 100, width: 300, height: 200))

        XCTAssertTrue(overlay.isCropping)
        XCTAssertEqual(overlay.cropRect, CGRect(x: 80, y: 120, width: 240, height: 160))
    }

    func testMoveCropStaysInsideImageBounds() {
        let overlay = CropOverlayView()
        overlay.beginCropping(in: CGRect(x: 50, y: 50, width: 200, height: 100))

        overlay.moveCrop(by: CGPoint(x: 1_000, y: 1_000))

        XCTAssertEqual(overlay.cropRect.maxX, 250)
        XCTAssertEqual(overlay.cropRect.maxY, 150)
        XCTAssertEqual(overlay.cropRect.width, 160)
        XCTAssertEqual(overlay.cropRect.height, 80)
    }

    func testResizeCropMaintainsMinimumSizeAndImageBounds() {
        let overlay = CropOverlayView()
        overlay.beginCropping(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        overlay.resizeCrop(edge: .topLeft, by: CGPoint(x: 1_000, y: 1_000))

        XCTAssertEqual(overlay.cropRect.maxX, 90)
        XCTAssertEqual(overlay.cropRect.maxY, 90)
        XCTAssertEqual(overlay.cropRect.width, 24)
        XCTAssertEqual(overlay.cropRect.height, 24)
    }
}
