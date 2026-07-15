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
        let version = CurrentFileVersion(
            device: 1,
            inode: 1,
            fileSize: 1,
            modificationNanoseconds: 1,
            changeNanoseconds: 1
        )
        await cache.insert(decoded, for: url, version: version)

        let started = ContinuousClock.now
        let cached = await cache.image(for: url, matching: version)
        let elapsed = started.duration(to: .now)

        XCTAssertNotNil(cached)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    func testStandardImageSetMeetsColdDecodeP50AndP95Budgets() throws {
        let sizes = (0..<20).map { index in
            (width: 1_200 + (index % 5) * 160, height: 900 + (index % 4) * 120)
        }
        let urls = try sizes.map { try makePNG(width: $0.width, height: $0.height) }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

        let milliseconds = try urls.map { url -> Double in
            let started = ContinuousClock.now
            _ = try ImageDecodeService().decode(url: url, format: .png)
            return Self.milliseconds(started.duration(to: .now))
        }

        XCTAssertLessThanOrEqual(Self.percentile(milliseconds, 0.50), 300)
        XCTAssertLessThanOrEqual(Self.percentile(milliseconds, 0.95), 800)
    }

    func testPreloadedCacheHitP95MeetsNavigationBudget() async {
        let cache = ImageCache(costLimit: 10_000)
        let decoded = DecodedImage(
            cgImage: makeImage(width: 4, height: 3),
            pixelSize: CGSize(width: 4, height: 3),
            isAnimated: false
        )
        let url = URL(fileURLWithPath: "/tmp/preloaded-p95.png")
        let version = CurrentFileVersion(
            device: 1, inode: 2, fileSize: 1,
            modificationNanoseconds: 1, changeNanoseconds: 1
        )
        await cache.insert(decoded, for: url, version: version)
        var milliseconds: [Double] = []
        for _ in 0..<100 {
            let started = ContinuousClock.now
            _ = await cache.image(for: url, matching: version)
            milliseconds.append(Self.milliseconds(started.duration(to: .now)))
        }

        XCTAssertLessThanOrEqual(Self.percentile(milliseconds, 0.95), 100)
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

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * percentile)) - 1))
        return sorted[index]
    }
}
