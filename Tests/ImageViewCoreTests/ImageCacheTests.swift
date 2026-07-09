import XCTest
import CoreGraphics
@testable import ImageViewCore

final class ImageCacheTests: XCTestCase {
    func testCacheEvictsLeastRecentItemWhenCostLimitIsExceeded() async {
        let cache = ImageCache(costLimit: 10)
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)

        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/a.png"), cost: 6)
        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/b.png"), cost: 6)

        let first = await cache.image(for: URL(fileURLWithPath: "/tmp/a.png"))
        let second = await cache.image(for: URL(fileURLWithPath: "/tmp/b.png"))
        XCTAssertNil(first)
        XCTAssertNotNil(second)
    }

    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
