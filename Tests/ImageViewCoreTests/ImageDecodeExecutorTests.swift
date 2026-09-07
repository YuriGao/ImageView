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

    func testCancellingQueuedDecodePreventsItsBodyFromRunning() async throws {
        let executor = ImageDecodeExecutor(maxConcurrentDecodeCount: 1)
        let firstGate = BlockingDecodeGate()
        let cancelledBodyCount = DecodeExecutionCounter()
        let first = Task<DecodedImage, Error>.detached { @Sendable [executor, firstGate] in
            try await executor.decode {
                firstGate.beginAndWait()
                return Self.makeImage()
            }
        }
        while !firstGate.hasStarted {
            await Task.yield()
        }

        let queued = Task<DecodedImage, Error>.detached { @Sendable [executor, cancelledBodyCount] in
            try await executor.decode {
                cancelledBodyCount.increment()
                return Self.makeImage()
            }
        }
        await Task.yield()
        queued.cancel()
        firstGate.release()

        _ = try await first.value
        do {
            _ = try await queued.value
            XCTFail("Cancelled queued decode unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(cancelledBodyCount.value, 0)
    }

    func testVisibleConsumerPromotesQueuedPrefetchAheadOfBackgroundWork() async throws {
        let executor = ImageDecodeExecutor(maxConcurrentDecodeCount: 1)
        let gate = BlockingDecodeGate()
        let order = DecodeOrder()
        let blocker = Task<DecodedImage, Error>.detached { @Sendable [executor, gate] in try await executor.decode { gate.beginAndWait(); return Self.makeImage() } }
        while !gate.hasStarted { await Task.yield() }
        let background = Task<DecodedImage, Error>.detached { @Sendable [executor, order] in
            try await executor.decode(priority: ImageDecodePriority(interactive: false)) {
                order.append(1)
                return Self.makeImage()
            }
        }
        let promotedPriority = ImageDecodePriority(interactive: false)
        let promoted = Task<DecodedImage, Error>.detached { @Sendable [executor, order, promotedPriority] in
            try await executor.decode(priority: promotedPriority) {
                order.append(2)
                return Self.makeImage()
            }
        }
        while executor.operationCount < 3 { await Task.yield() }
        promotedPriority.promote()
        gate.release()
        _ = try await (blocker.value, background.value, promoted.value)
        XCTAssertEqual(order.values, [2, 1])
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

private final class BlockingDecodeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false

    var hasStarted: Bool { lock.withLock { started } }

    func beginAndWait() {
        lock.withLock { started = true }
        semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}

private final class DecodeExecutionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
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

private final class DecodeOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []
    var values: [Int] { lock.withLock { storage } }
    func append(_ value: Int) { lock.withLock { storage.append(value) } }
}
