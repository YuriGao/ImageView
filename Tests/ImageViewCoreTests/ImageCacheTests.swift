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

    func testCacheReadUpdatesRecencyBeforeEviction() async {
        let cache = ImageCache(costLimit: 12)
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let firstURL = URL(fileURLWithPath: "/tmp/a.png")
        let secondURL = URL(fileURLWithPath: "/tmp/b.png")
        let thirdURL = URL(fileURLWithPath: "/tmp/c.png")

        await cache.insert(image, for: firstURL, cost: 4)
        await cache.insert(image, for: secondURL, cost: 4)
        let warmedFirst = await cache.image(for: firstURL)
        XCTAssertNotNil(warmedFirst)

        await cache.insert(image, for: thirdURL, cost: 5)

        let first = await cache.image(for: firstURL)
        let second = await cache.image(for: secondURL)
        let third = await cache.image(for: thirdURL)

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
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
