import AppKit
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

@MainActor
final class AnimationPlayerTests: XCTestCase {
    func testFramePrefetchRunsOffMainThreadAndKeepsBoundedLookAhead() async throws {
        let image = makeImage()
        let source = AnimatedFrameSource(frameCount: 100) { _ in
            XCTAssertFalse(Thread.isMainThread)
            return AnimatedFrame(cgImage: image.cgImage, duration: 10)
        }
        let player = AnimationPlayer()
        player.configure(DecodedImage(cgImage: image.cgImage, pixelSize: image.pixelSize, isAnimated: true, animationFrameSource: source))
        for _ in 0..<200 where player.bufferedFrameCount < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(player.currentFrame)
        XCTAssertEqual(player.bufferedFrameCount, 2)
        for index in 1...8 {
            player.advance()
            for _ in 0..<200 where player.bufferedFrameCount < 2 { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(player.currentIndex, index)
            XCTAssertLessThanOrEqual(player.bufferedFrameCount, AnimationPlayer.maximumBufferedFrameCount)
            XCTAssertLessThanOrEqual(player.bufferedByteCost, AnimationPlayer.maximumBufferedByteCost)
        }
        player.configure(nil)
        XCTAssertFalse(player.isRunning)
        XCTAssertEqual(player.bufferedFrameCount, 0)
    }

    func testReplacingImageRejectsLateFrameFromOldSource() async throws {
        let image = makeImage()
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "frame decode started")
        let source = AnimatedFrameSource(frameCount: 2) { _ in
            started.fulfill()
            _ = gate.wait(timeout: .now() + 3)
            return AnimatedFrame(cgImage: image.cgImage, duration: 1)
        }
        let player = AnimationPlayer()
        player.configure(DecodedImage(cgImage: image.cgImage, pixelSize: image.pixelSize, isAnimated: true, animationFrameSource: source))
        await fulfillment(of: [started], timeout: 2)
        player.configure(image)
        gate.signal()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(player.isRunning)
        XCTAssertNil(player.currentFrame)
        XCTAssertEqual(player.bufferedFrameCount, 0)
    }

    func testPlaybackDeadlineCompensatesForLateFrameInsteadOfAddingAnotherFullDuration() {
        XCTAssertEqual(AnimationPlayer.nextDeadline(previous: 10, duration: 0.1, now: 10.08), 10.1, accuracy: 0.0001)
        XCTAssertEqual(AnimationPlayer.nextDeadline(previous: 10, duration: 0.1, now: 10.2), 10.2, accuracy: 0.0001)
    }

    private func makeImage() -> DecodedImage {
        let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return DecodedImage(cgImage: context.makeImage()!, pixelSize: CGSize(width: 4, height: 3), isAnimated: false)
    }
}
