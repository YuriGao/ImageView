import CoreGraphics
import XCTest
@testable import ImageViewCore

final class ImageEditingServiceTests: XCTestCase {
    func testHorizontalMirrorKeepsImageSize() throws {
        let image = makeImage(width: 3, height: 2)
        let result = try ImageEditingService().apply([.mirrorHorizontal], to: image)
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 2)
    }

    func testUnsupportedSaveFormatThrows() {
        let image = makeImage(width: 2, height: 2)
        XCTAssertThrowsError(
            try ImageEditingService().save(
                image,
                to: URL(fileURLWithPath: "/tmp/a.svg"),
                format: .svg
            )
        )
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
