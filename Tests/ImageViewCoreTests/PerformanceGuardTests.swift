import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewCore

final class PerformanceGuardTests: XCTestCase {
    func testDirectoryScanDoesNotRequireImageDecoding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<1000 {
            FileManager.default.createFile(atPath: root.appendingPathComponent("image-\(index).png").path, contents: Data())
        }

        let opened = root.appendingPathComponent("image-500.png")
        let started = ContinuousClock.now
        let items = try await DirectoryScanner().scan(containing: opened)
        let elapsed = started.duration(to: .now)
        XCTAssertEqual(items.count, 1000)
        XCTAssertLessThan(elapsed, .milliseconds(300))
    }

    func testTypicalImageFirstDecodeMeetsVisibleContentBudget() throws {
        let url = try makePNG(width: 1_600, height: 1_200)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let started = ContinuousClock.now
        let image = try ImageDecodeService().decode(url: url, format: .png)
        let elapsed = started.duration(to: .now)

        XCTAssertEqual(image.pixelSize, CGSize(width: 1_600, height: 1_200))
        XCTAssertLessThan(elapsed, .milliseconds(300))
    }

    func testPreloadedImageCacheHitMeetsNavigationBudget() async {
        let cache = ImageCache(costLimit: 10_000)
        let image = makeImage(width: 4, height: 3)
        let decoded = DecodedImage(cgImage: image, pixelSize: CGSize(width: 4, height: 3), isAnimated: false)
        let url = URL(fileURLWithPath: "/tmp/preloaded.png")
        await cache.insert(decoded, for: url)

        let started = ContinuousClock.now
        let cached = await cache.image(for: url)
        let elapsed = started.duration(to: .now)

        XCTAssertNotNil(cached)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    private func makePNG(width: Int, height: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("typical.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, makeImage(width: width, height: height), nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.cannotCreateDestination }
        return url
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

    private enum TestError: Error {
        case cannotCreateDestination
    }
}
