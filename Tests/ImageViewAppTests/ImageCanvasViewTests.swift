import AppKit
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class ImageCanvasViewTests: XCTestCase {
    func testRightClickMenuUsesContextMenuProvider() throws {
        let canvas = ImageCanvasView()
        let expectedMenu = NSMenu(title: "Image Actions")
        expectedMenu.addItem(withTitle: "Copy Image", action: nil, keyEquivalent: "")
        canvas.contextMenuProvider = { expectedMenu }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        XCTAssertTrue(canvas.menu(for: event) === expectedMenu)
    }

    func testZoomAtCanvasCenterKeepsZeroOffset() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 400, height: 300)

        canvas.zoom(by: 2, around: CGPoint(x: 200, y: 150))

        XCTAssertEqual(canvas.offset.x, 0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 0, accuracy: 0.001)
    }

    func testZoomOffCenterPreservesCanvasAnchor() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 400, height: 300)

        canvas.zoom(by: 2, around: CGPoint(x: 300, y: 150))

        XCTAssertEqual(canvas.offset.x, -100, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 0, accuracy: 0.001)
    }

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
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(canvas.pixelScale!, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.displayMode, .manual)

        canvas.toggleFitOrActualSize()
        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset, .zero)
        XCTAssertEqual(canvas.displayMode, .fit)
    }

    func testToggleRestoresLastManualPixelScale() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)
        canvas.setManualPercentage(200)
        canvas.resetViewTransform()

        canvas.toggleFitOrActualSize()

        XCTAssertEqual(canvas.pixelScale!, 2.0, accuracy: 0.001)
        XCTAssertEqual(canvas.displayMode, .manual)
    }

    func testManualPixelScaleSurvivesCanvasResize() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)
        canvas.zoomToActualSize()

        canvas.setFrameSize(CGSize(width: 800, height: 600))

        XCTAssertEqual(canvas.pixelScale!, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.displayMode, .manual)
    }

    func testFitModeReportsPixelScaleWhenCanvasResizeCrossesActualSize() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)
        var reportedPixelScales: [CGFloat] = []
        canvas.onTransformChanged = { _ in
            if let pixelScale = canvas.pixelScale {
                reportedPixelScales.append(pixelScale)
            }
        }

        canvas.setFrameSize(CGSize(width: 800, height: 600))
        canvas.setFrameSize(CGSize(width: 200, height: 150))

        XCTAssertEqual(reportedPixelScales.count, 2)
        XCTAssertEqual(reportedPixelScales[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(reportedPixelScales[1], 0.25, accuracy: 0.001)
        XCTAssertEqual(canvas.displayMode, .fit)
    }

    func testManualPixelScaleSurvivesPreviewReplacementWithFullResolutionImage() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)
        canvas.zoomToActualSize()

        canvas.image = makeDecodedImage(width: 1_600, height: 1_200)

        XCTAssertEqual(canvas.pixelScale!, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.scale, 4.0, accuracy: 0.001)
        XCTAssertEqual(canvas.displayMode, .manual)
    }

    func testManualFocusSurvivesPreviewReplacementWithFullResolutionImage() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600)
        canvas.zoomToActualSize()
        canvas.pan(by: CGPoint(x: -100, y: -50))

        canvas.image = makeDecodedImage(width: 1_600, height: 1_200)

        XCTAssertEqual(canvas.pixelScale!, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.x, -200, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, -100, accuracy: 0.001)
    }

    func testDownsampledPreviewReplacementKeepsDrawRectStable() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600, sourceWidth: 1_600, sourceHeight: 1_200)
        canvas.setManualPercentage(50)
        canvas.pan(by: CGPoint(x: -120, y: -60))
        let previewDrawRect = canvas.imageDrawRect

        canvas.image = makeDecodedImage(width: 1_600, height: 1_200)

        XCTAssertEqual(canvas.imageDrawRect?.origin.x ?? 0, previewDrawRect?.origin.x ?? 0, accuracy: 0.001)
        XCTAssertEqual(canvas.imageDrawRect?.origin.y ?? 0, previewDrawRect?.origin.y ?? 0, accuracy: 0.001)
        XCTAssertEqual(canvas.imageDrawRect?.width ?? 0, previewDrawRect?.width ?? 0, accuracy: 0.001)
        XCTAssertEqual(canvas.imageDrawRect?.height ?? 0, previewDrawRect?.height ?? 0, accuracy: 0.001)
        XCTAssertEqual(canvas.pixelScale!, 0.5, accuracy: 0.001)
    }

    func testDownsampledPreviewUsesSourcePixelsForActualSize() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 800, height: 600, sourceWidth: 1_600, sourceHeight: 1_200)

        canvas.zoomToActualSize()

        XCTAssertEqual(canvas.imageDrawRect?.width ?? 0, 1_600, accuracy: 0.001)
        XCTAssertEqual(canvas.imageDrawRect?.height ?? 0, 1_200, accuracy: 0.001)
        XCTAssertEqual(canvas.pixelScale!, 1, accuracy: 0.001)
    }

    func testActualSizeRemainsOnePixelPerPointForVeryLargeImage() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 40_000, height: 30_000)

        canvas.zoomToActualSize()

        XCTAssertEqual(canvas.pixelScale!, 1.0, accuracy: 0.001)
        XCTAssertEqual(canvas.scale, 100.0, accuracy: 0.001)
    }

    func testManualPercentageClampsInActualPixelScaleNotFitRelativeScale() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 40_000, height: 30_000)

        canvas.setManualPercentage(5_000)

        XCTAssertEqual(canvas.pixelScale!, 12.0, accuracy: 0.001)
    }

    func testFitWidthMakesLongImageScrollableAtCanvasWidth() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        canvas.image = makeDecodedImage(width: 1_000, height: 5_000)

        canvas.zoomToFitWidth()

        XCTAssertEqual(canvas.displayMode, .fitWidth)
        XCTAssertEqual(canvas.imageDrawRect?.width ?? 0, 400, accuracy: 0.001)
        canvas.handleScroll(deltaX: 0, deltaY: 80, at: .zero)
        XCTAssertLessThan(canvas.offset.y, 0)
    }

    func testScrollPansWhenZoomed() {
        let canvas = ImageCanvasView()
        canvas.scale = 2.0

        canvas.handleScroll(
            deltaX: 8,
            deltaY: -12,
            at: CGPoint(x: 10, y: 10),
            isDirectionInvertedFromDevice: true
        )

        XCTAssertEqual(canvas.offset.x, -8, accuracy: 0.001)
        XCTAssertEqual(canvas.offset.y, 12, accuracy: 0.001)
    }

    func testSystemAdjustedPositiveScrollZoomsOutRegardlessOfDeviceInversion() {
        for isInverted in [false, true] {
            let canvas = ImageCanvasView()
            canvas.scale = 2

            canvas.handleScroll(
                deltaX: 0,
                deltaY: 10,
                at: CGPoint(x: 40, y: 30),
                modifierFlags: [.option],
                isDirectionInvertedFromDevice: isInverted
            )

            XCTAssertLessThan(canvas.scale, 2)
        }
    }

    func testSystemAdjustedNegativeScrollZoomsInRegardlessOfDeviceInversion() {
        for isInverted in [false, true] {
            let canvas = ImageCanvasView()
            canvas.scale = 2

            canvas.handleScroll(
                deltaX: 0,
                deltaY: -10,
                at: CGPoint(x: 40, y: 30),
                modifierFlags: [.option],
                isDirectionInvertedFromDevice: isInverted
            )

            XCTAssertGreaterThan(canvas.scale, 2)
        }
    }

    func testSystemAdjustedPositiveHorizontalScrollNavigatesPreviousOnceAfterThreshold() {
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

    func testSystemAdjustedPositiveHorizontalScrollNavigatesPreviousWhenDirectionIsInvertedFromDevice() {
        let canvas = ImageCanvasView()
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(
            deltaX: 80,
            deltaY: 2,
            at: .zero,
            isDirectionInvertedFromDevice: true
        )

        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 1)
    }

    func testSystemAdjustedNegativeHorizontalScrollNavigatesNextRegardlessOfDeviceInversion() {
        for isInverted in [false, true] {
            let canvas = ImageCanvasView()
            var nextCount = 0
            var previousCount = 0
            canvas.onNext = { nextCount += 1 }
            canvas.onPrevious = { previousCount += 1 }

            canvas.handleScroll(
                deltaX: -80,
                deltaY: 0,
                at: .zero,
                isDirectionInvertedFromDevice: isInverted
            )

            XCTAssertEqual(nextCount, 1)
            XCTAssertEqual(previousCount, 0)
        }
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

    func testNonPreciseHorizontalWheelDoesNotNavigate() {
        let canvas = ImageCanvasView()
        var nextCount = 0
        var previousCount = 0
        canvas.onNext = { nextCount += 1 }
        canvas.onPrevious = { previousCount += 1 }

        canvas.handleScroll(
            deltaX: 160,
            deltaY: 0,
            at: .zero,
            hasPreciseScrollingDeltas: false
        )

        XCTAssertEqual(nextCount, 0)
        XCTAssertEqual(previousCount, 0)
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

    func testAnimationRunsFromOnDemandFullResolutionFrameSource() {
        let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let first = makeDecodedImage(width: 4, height: 3)
        let second = makeDecodedImage(width: 8, height: 6)
        let frameSource = AnimatedFrameSource(frameCount: 2) { index in
            let image = index == 0 ? first.cgImage : second.cgImage
            return AnimatedFrame(cgImage: image, duration: 1)
        }
        canvas.image = DecodedImage(
            cgImage: first.cgImage,
            pixelSize: first.pixelSize,
            isAnimated: true,
            animationFrameSource: frameSource
        )

        XCTAssertTrue(canvas.isAnimating)
        XCTAssertEqual(canvas.currentAnimationFrameIndex, 0)

        canvas.advanceAnimationFrame()

        XCTAssertEqual(canvas.currentAnimationFrameIndex, 1)
    }

    private func makeDecodedImage(
        width: Int,
        height: Int,
        sourceWidth: Int? = nil,
        sourceHeight: Int? = nil
    ) -> DecodedImage {
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
            isAnimated: false,
            sourcePixelSize: CGSize(
                width: sourceWidth ?? width,
                height: sourceHeight ?? height
            ),
            isFullResolution: sourceWidth == nil && sourceHeight == nil
        )
    }
}
