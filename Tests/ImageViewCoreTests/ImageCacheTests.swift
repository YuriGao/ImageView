import XCTest
import CoreGraphics
@testable import ImageViewCore

final class ImageCacheTests: XCTestCase {
    private let version = CurrentFileVersion(
        device: 1,
        inode: 1,
        fileSize: 1,
        modificationNanoseconds: 1,
        changeNanoseconds: 1
    )

    func testCacheEvictsLeastRecentItemWhenCostLimitIsExceeded() async {
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let cache = ImageCache(costLimit: image.decodedByteCost * 2 - 1)

        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/a.png"), version: version)
        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/b.png"), version: version)

        let first = await cache.image(for: URL(fileURLWithPath: "/tmp/a.png"), matching: version)
        let second = await cache.image(for: URL(fileURLWithPath: "/tmp/b.png"), matching: version)
        XCTAssertNil(first)
        XCTAssertNotNil(second)
    }

    func testCacheReadUpdatesRecencyBeforeEviction() async {
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let cache = ImageCache(costLimit: image.decodedByteCost * 2)
        let firstURL = URL(fileURLWithPath: "/tmp/a.png")
        let secondURL = URL(fileURLWithPath: "/tmp/b.png")
        let thirdURL = URL(fileURLWithPath: "/tmp/c.png")

        await cache.insert(image, for: firstURL, version: version)
        await cache.insert(image, for: secondURL, version: version)
        let warmedFirst = await cache.image(for: firstURL, matching: version)
        XCTAssertNotNil(warmedFirst)

        await cache.insert(image, for: thirdURL, version: version)

        let first = await cache.image(for: firstURL, matching: version)
        let second = await cache.image(for: secondURL, matching: version)
        let third = await cache.image(for: thirdURL, matching: version)

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

        await cache.insert(staticImage, for: staticURL, version: version)
        await cache.insert(animatedImage, for: animatedURL, version: version)

        let cachedStatic = await cache.image(for: staticURL, matching: version)
        let cachedAnimation = await cache.image(for: animatedURL, matching: version)
        XCTAssertNil(cachedStatic)
        XCTAssertNotNil(cachedAnimation)
    }

    func testVersionMismatchEvictsCachedImage() async {
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
        let cache = ImageCache(costLimit: image.decodedByteCost)
        let url = URL(fileURLWithPath: "/tmp/versioned.png")
        let originalVersion = makeVersion(inode: 1, changeNanoseconds: 1)
        let replacementVersion = makeVersion(inode: 2, changeNanoseconds: 2)

        await cache.insert(image, for: url, version: originalVersion)

        let mismatched = await cache.image(for: url, matching: replacementVersion)
        let evicted = await cache.image(for: url, matching: originalVersion)
        XCTAssertNil(mismatched)
        XCTAssertNil(evicted)
    }

    private func makeVersion(inode: UInt64, changeNanoseconds: Int64) -> CurrentFileVersion {
        CurrentFileVersion(
            device: 1,
            inode: inode,
            fileSize: 100,
            modificationNanoseconds: 1,
            changeNanoseconds: changeNanoseconds
        )
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
