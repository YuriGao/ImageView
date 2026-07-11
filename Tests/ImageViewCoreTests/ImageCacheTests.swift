import XCTest
import CoreGraphics
@testable import ImageViewCore

final class ImageCacheTests: XCTestCase {
    func testCacheEvictsLeastRecentItemWhenCostLimitIsExceeded() async {
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let cache = ImageCache(costLimit: image.decodedByteCost * 2 - 1)

        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/a.png"))
        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/b.png"))

        let first = await cache.image(for: URL(fileURLWithPath: "/tmp/a.png"))
        let second = await cache.image(for: URL(fileURLWithPath: "/tmp/b.png"))
        XCTAssertNil(first)
        XCTAssertNotNil(second)
    }

    func testCacheReadUpdatesRecencyBeforeEviction() async {
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let cache = ImageCache(costLimit: image.decodedByteCost * 2)
        let firstURL = URL(fileURLWithPath: "/tmp/a.png")
        let secondURL = URL(fileURLWithPath: "/tmp/b.png")
        let thirdURL = URL(fileURLWithPath: "/tmp/c.png")

        await cache.insert(image, for: firstURL)
        await cache.insert(image, for: secondURL)
        let warmedFirst = await cache.image(for: firstURL)
        XCTAssertNotNil(warmedFirst)

        await cache.insert(image, for: thirdURL)

        let first = await cache.image(for: firstURL)
        let second = await cache.image(for: secondURL)
        let third = await cache.image(for: thirdURL)

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
    }

    func testCacheCalculatesAnimatedImageCostFromDecodedImage() async {
        let main = makeImage()
        let staticImage = DecodedImage(cgImage: main, pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let animatedImage = DecodedImage(
            cgImage: main,
            pixelSize: CGSize(width: 1, height: 1),
            isAnimated: true,
            animationFrames: [AnimatedFrame(cgImage: makeImage(), duration: 0.1)]
        )
        let cache = ImageCache(costLimit: animatedImage.decodedByteCost)
        let staticURL = URL(fileURLWithPath: "/tmp/static.png")
        let animatedURL = URL(fileURLWithPath: "/tmp/animated.gif")

        await cache.insert(staticImage, for: staticURL)
        await cache.insert(animatedImage, for: animatedURL)

        let cachedStatic = await cache.image(for: staticURL)
        let cachedAnimation = await cache.image(for: animatedURL)
        XCTAssertNil(cachedStatic)
        XCTAssertNotNil(cachedAnimation)
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
