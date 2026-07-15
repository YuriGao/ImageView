import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class GestureCoordinatorTests: XCTestCase {
    func testTwoFingerTapTogglesFitAndActualSize() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let context = CGContext(
            data: nil,
            width: 800,
            height: 600,
            bitsPerComponent: 8,
            bytesPerRow: 800 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        canvas.image = DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: 800, height: 600),
            isAnimated: false
        )
        let coordinator = GestureCoordinator(canvas: canvas)

        coordinator.applyTwoFingerTap()
        XCTAssertEqual(canvas.scale, 2, accuracy: 0.001)
        XCTAssertEqual(canvas.pixelScale!, 1, accuracy: 0.001)

        coordinator.applyTwoFingerTap()
        XCTAssertEqual(canvas.scale, 1, accuracy: 0.001)
    }
}
