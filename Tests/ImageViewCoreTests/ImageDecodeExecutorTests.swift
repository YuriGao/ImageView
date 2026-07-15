import CoreGraphics
import XCTest
@testable import ImageViewCore

final class ImageDecodeExecutorTests: XCTestCase {
    func testExecutorHonorsProcessConcurrencyLimit() async throws {
        let executor = ImageDecodeExecutor(maxConcurrentDecodeCount: 2)
        let concurrency = DecodeConcurrencyCounter()

        try await withThrowingTaskGroup(of: DecodedImage.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await executor.decode {
                        concurrency.begin()
                        defer { concurrency.end() }
                        Thread.sleep(forTimeInterval: 0.03)
                        return Self.makeImage()
                    }
                }
            }
            for try await _ in group {}
        }

        XCTAssertLessThanOrEqual(concurrency.maximum, 2)
    }

    private static func makeImage() -> DecodedImage {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        return DecodedImage(cgImage: image, pixelSize: CGSize(width: 1, height: 1), isAnimated: false)
    }
}

private final class DecodeConcurrencyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var peak = 0

    var maximum: Int { lock.withLock { peak } }

    func begin() {
        lock.withLock {
            current += 1
            peak = max(peak, current)
        }
    }

    func end() {
        lock.withLock { current -= 1 }
    }
}
