import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class ThumbnailProviderTests: XCTestCase {
    func testCancellationPreventsCompletion() {
        let provider = ThumbnailProvider(loader: { _, _, completion in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion(.success(NSImage(size: NSSize(width: 12, height: 12))))
            }
            return {}
        })
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/cancel-me.png"), format: .png)
        let completionNotCalled = expectation(description: "completion not called after cancellation")
        completionNotCalled.isInverted = true

        let request = provider.loadThumbnail(for: item) { _ in
            completionNotCalled.fulfill()
        }
        request.cancel()

        wait(for: [completionNotCalled], timeout: 0.15)
    }

    func testDefaultProviderReusesVersionedCache() throws {
        ThumbnailProvider.removeAllCachedThumbnailsForTesting()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cached.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let version = CurrentFileVersion(
            device: 1,
            inode: 1,
            fileSize: 1,
            modificationNanoseconds: 1,
            changeNanoseconds: 1
        )
        let provider = ThumbnailProvider(currentFileVersionAtURL: { _ in version })
        let item = ImageItem(url: url, format: .png)
        let firstLoaded = expectation(description: "first thumbnail")
        let firstRequest = provider.loadThumbnail(for: item) { result in
            if case .success = result { firstLoaded.fulfill() }
        }
        wait(for: [firstLoaded], timeout: 1)
        withExtendedLifetime(firstRequest) {}
        try FileManager.default.removeItem(at: url)

        let cachedLoaded = expectation(description: "cached thumbnail")
        let secondRequest = provider.loadThumbnail(for: item) { result in
            if case .success = result { cachedLoaded.fulfill() }
        }
        wait(for: [cachedLoaded], timeout: 0.2)
        withExtendedLifetime(secondRequest) {}
    }

    func testCancellingQueuedDefaultRequestPreventsDecodeFromStarting() throws {
        ThumbnailProvider.removeAllCachedThumbnailsForTesting()
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "four active decodes")
        started.expectedFulfillmentCount = ThumbnailProvider.maximumConcurrentDecodeCount
        let completed = expectation(description: "four active requests complete")
        completed.expectedFulfillmentCount = ThumbnailProvider.maximumConcurrentDecodeCount
        let cancelledCompletion = expectation(description: "cancelled request does not complete")
        cancelledCompletion.isInverted = true
        let decodeCount = ThumbnailLockedCounter()
        let version = CurrentFileVersion(
            device: 2,
            inode: 2,
            fileSize: 2,
            modificationNanoseconds: 2,
            changeNanoseconds: 2
        )
        let image = try Self.makeDecodedImage()
        let provider = ThumbnailProvider(
            currentFileVersionAtURL: { _ in version },
            decoder: { _, _ in
                decodeCount.increment()
                started.fulfill()
                gate.wait()
                return image
            }
        )

        let activeRequests = (0..<ThumbnailProvider.maximumConcurrentDecodeCount).map { index in
            provider.loadThumbnail(
                for: ImageItem(url: URL(fileURLWithPath: "/tmp/active-\(index).png"), format: .png)
            ) { _ in
                completed.fulfill()
            }
        }
        wait(for: [started], timeout: 1)

        let cancelledRequest = provider.loadThumbnail(
            for: ImageItem(url: URL(fileURLWithPath: "/tmp/queued-cancel.png"), format: .png)
        ) { _ in
            cancelledCompletion.fulfill()
        }
        cancelledRequest.cancel()
        for _ in 0..<ThumbnailProvider.maximumConcurrentDecodeCount {
            gate.signal()
        }

        wait(for: [completed, cancelledCompletion], timeout: 1)
        XCTAssertEqual(decodeCount.value, ThumbnailProvider.maximumConcurrentDecodeCount)
        withExtendedLifetime(activeRequests) {}
    }

    private static func makeDecodedImage() throws -> DecodedImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return DecodedImage(
            cgImage: try XCTUnwrap(bitmap.cgImage),
            pixelSize: CGSize(width: 1, height: 1),
            isAnimated: false
        )
    }
}

private final class ThumbnailLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int { lock.withLock { storage } }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
