import AppKit
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class ImageCanvasViewTests: XCTestCase {
    func testTransformHelpersUpdateScaleAndOffset() {
        let canvas = ImageCanvasView()

        canvas.zoom(by: 2.0, around: CGPoint(x: 20, y: 10))
        canvas.pan(by: CGPoint(x: 6, y: -4))

        XCTAssertEqual(canvas.scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.x, -14, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, -14, accuracy: 0.001)

        canvas.resetViewTransform()

        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset, .zero)
    }

    func testToggleFitOrActualSizeSwitchesBetweenZoomedAndFit() {
        let canvas = ImageCanvasView()

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 2.0, accuracy: 0.001)

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset, .zero)
    }

    func testScrollPansWhenZoomed() {
        let canvas = ImageCanvasView()
        canvas.scale = 2.0

        canvas.handleScroll(deltaX: 8, deltaY: -12, at: CGPoint(x: 10, y: 10))

        XCTAssertEqual(canvas.offset.x, -8, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 12, accuracy: 0.001)
    }

    func testScrollZoomsWhenUsingZoomModifier() {
        let canvas = ImageCanvasView()
        canvas.scale = 2.0

        canvas.handleScroll(deltaX: 0, deltaY: -10, at: CGPoint(x: 40, y: 30), modifierFlags: [.option])

        XCTAssertGreaterThan(canvas.scale, 2.0)
    }

    func testHorizontalTrackpadScrollUsesNaturalNavigationDirectionOnceAfterThreshold() {
        let canvas = ImageCanvasView()
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(deltaX: 25, deltaY: 2, at: .zero)
        canvas.handleScroll(deltaX: 25, deltaY: 2, at: .zero)
        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 0)

        canvas.handleScroll(deltaX: 35, deltaY: 2, at: .zero)
        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 1)

        canvas.handleScroll(deltaX: 40, deltaY: 2, at: .zero)
        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 1)
    }

    func testTrackpadSwipeResetsAfterGestureEnds() {
        let canvas = ImageCanvasView()
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(deltaX: 40, deltaY: 0, at: .zero, phase: .began)
        canvas.handleScroll(deltaX: 40, deltaY: 0, at: .zero, phase: .ended)
        XCTAssertEqual(previousCount, 1)

        canvas.handleScroll(deltaX: -80, deltaY: 0, at: .zero, phase: .ended)
        XCTAssertEqual(nextCount, 1)
    }

    func testTrackpadMomentumDoesNotTriggerSecondNavigation() {
        let canvas = ImageCanvasView()
        var previousCount = 0
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(deltaX: 80, deltaY: 0, at: .zero, phase: .ended)
        canvas.handleScroll(deltaX: 80, deltaY: 0, at: .zero, momentumPhase: .began)

        XCTAssertEqual(previousCount, 1)
    }

    func testHorizontalTrackpadScrollPansAtZoomedHorizontalEdgeWithoutNavigating() {
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 400, height: 300)
        canvas.scale = 2
        canvas.offset = CGPoint(x: 200, y: 0)
        var nextCount = 0
        canvas.onNext = { nextCount += 1 }

        canvas.handleScroll(deltaX: 25, deltaY: 0, at: .zero)

        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(canvas.offset.x, 175, accuracy: 0.001)
    }

    func testMouseDragPansOnlyWhenZoomed() {
        let canvas = ImageCanvasView()

        canvas.beginMouseDrag(at: CGPoint(x: 10, y: 10))
        canvas.continueMouseDrag(to: CGPoint(x: 30, y: 20))
        XCTAssertEqual(canvas.offset, .zero)

        canvas.scale = 2.0
        canvas.beginMouseDrag(at: CGPoint(x: 10, y: 10))
        canvas.continueMouseDrag(to: CGPoint(x: 30, y: 20))
        canvas.endMouseDrag()

        XCTAssertEqual(canvas.offset.x, 20, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 10, accuracy: 0.001)
    }

    func testPixelCropRectConvertsCanvasCoordinatesToSourcePixels() {
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 200, height: 100)

        let result = canvas.pixelCropRect(for: CGRect(x: 40, y: 90, width: 320, height: 160))

        XCTAssertEqual(result, CGRect(x: 20, y: 20, width: 160, height: 80))
    }

    func testPixelCropRectClampsToVisibleSourceBounds() {
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 200, height: 100)

        let result = canvas.pixelCropRect(for: CGRect(x: -10, y: 20, width: 70, height: 70))

        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 30, height: 20))
    }

    func testClampedOffsetKeepsZoomedImageCoveringCanvas() {
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 400, height: 300)
        canvas.scale = 2

        XCTAssertEqual(canvas.clampedOffset(for: CGPoint(x: 1_000, y: -1_000)), CGPoint(x: 200, y: -150))
    }

    func testAnimationRunsOnlyForAnimatedImages() {
        let canvas = ImageCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let first = makeDecodedImage(width: 4, height: 3)
        let second = makeDecodedImage(width: 4, height: 3)
        canvas.image = DecodedImage(
            cgImage: first.cgImage,
            pixelSize: first.pixelSize,
            isAnimated: true,
            animationFrames: [
                AnimatedFrame(cgImage: first.cgImage, duration: 1),
                AnimatedFrame(cgImage: second.cgImage, duration: 1)
            ]
        )

        XCTAssertTrue(canvas.isAnimating)
        canvas.advanceAnimationFrame()
        XCTAssertEqual(canvas.currentAnimationFrameIndex, 1)

        canvas.image = first
        XCTAssertFalse(canvas.isAnimating)
    }

    private func makeDecodedImage(width: Int, height: Int) -> DecodedImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: width, height: height),
            isAnimated: false
        )
    }
}
