import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewCore

final class ImageDecodeServiceTests: XCTestCase {
    func testDecodeGeneratedPngThroughImageIO() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("sample.png")
        try makePNGData(width: 4, height: 3).write(to: url)

        let decoded = try ImageDecodeService().decode(url: url, format: .png, maxPixelSize: nil)

        XCTAssertEqual(decoded.pixelSize.width, 4)
        XCTAssertEqual(decoded.pixelSize.height, 3)
        XCTAssertEqual(decoded.sourcePixelSize, CGSize(width: 4, height: 3))
        XCTAssertTrue(decoded.isFullResolution)
        XCTAssertFalse(decoded.isAnimated)
    }

    func testExplicitPreviewReportsSourceSizeAndDownsampling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preview.png")
        try makePNGData(width: 400, height: 200).write(to: url)

        let preview = try ImageDecodeService().decode(
            url: url,
            format: .png,
            purpose: .preview(maxPixelSize: 100)
        )

        XCTAssertEqual(preview.pixelSize, CGSize(width: 100, height: 50))
        XCTAssertEqual(preview.sourcePixelSize, CGSize(width: 400, height: 200))
        XCTAssertFalse(preview.isFullResolution)
    }

    func testPreviewThatDoesNotDownsampleIsFullResolution() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("small-preview.png")
        try makePNGData(width: 4, height: 3).write(to: url)

        let preview = try ImageDecodeService().decode(
            url: url,
            format: .png,
            purpose: .preview(maxPixelSize: 100)
        )

        XCTAssertEqual(preview.pixelSize, CGSize(width: 4, height: 3))
        XCTAssertEqual(preview.sourcePixelSize, CGSize(width: 4, height: 3))
        XCTAssertTrue(preview.isFullResolution)
    }

    func testARWThumbnailAndPreviewPreferEmbeddedThumbnailButFullDecodeUsesPrimaryImage() {
        let thumbnail = ImageDecodeService.imageIODecodePlan(
            format: .arw,
            purpose: .thumbnail(maxPixelSize: 320),
            sourceMaxPixelSize: 9_504
        )
        let preview = ImageDecodeService.imageIODecodePlan(
            format: .arw,
            purpose: .preview(maxPixelSize: 2_048),
            sourceMaxPixelSize: 9_504
        )
        let full = ImageDecodeService.imageIODecodePlan(
            format: .arw,
            purpose: .full,
            sourceMaxPixelSize: 9_504
        )

        XCTAssertEqual(thumbnail.thumbnailSource, .embeddedThumbnailIfAvailable)
        XCTAssertEqual(thumbnail.maxPixelSize, 320)
        XCTAssertFalse(thumbnail.loadsAnimationFrames)
        XCTAssertEqual(thumbnail.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageIfAbsent] as? Bool, true)
        XCTAssertNil(thumbnail.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageAlways])

        XCTAssertEqual(preview.thumbnailSource, .embeddedThumbnailIfAvailable)
        XCTAssertEqual(preview.maxPixelSize, 2_048)
        XCTAssertFalse(preview.loadsAnimationFrames)
        XCTAssertEqual(preview.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageIfAbsent] as? Bool, true)
        XCTAssertNil(preview.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageAlways])

        XCTAssertEqual(full.thumbnailSource, .primaryImage)
        XCTAssertEqual(full.maxPixelSize, 9_504)
        XCTAssertTrue(full.loadsAnimationFrames)
        XCTAssertEqual(full.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageAlways] as? Bool, true)
        XCTAssertNil(full.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageIfAbsent])
    }

    func testNonRAWPreviewContinuesToDecodeFromPrimaryImage() {
        let preview = ImageDecodeService.imageIODecodePlan(
            format: .jpeg,
            purpose: .preview(maxPixelSize: 2_048),
            sourceMaxPixelSize: 9_504
        )

        XCTAssertEqual(preview.thumbnailSource, .primaryImage)
        XCTAssertEqual(preview.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageAlways] as? Bool, true)
        XCTAssertNil(preview.thumbnailOptions[kCGImageSourceCreateThumbnailFromImageIfAbsent])
    }

    func testARWFixturePreviewWhenProvided() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["IMAGEVIEW_RAW_FIXTURE"],
              !fixturePath.isEmpty else {
            throw XCTSkip("Set IMAGEVIEW_RAW_FIXTURE to an ARW file to run the optional integration test")
        }

        let url = URL(fileURLWithPath: fixturePath)
        XCTAssertEqual(SupportedImageFormat(fileExtension: url.pathExtension), .arw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let expectedSourcePixelSize = try XCTUnwrap(ImageDecodeService.orientedPixelSize(properties: properties))
        XCTAssertGreaterThan(max(expectedSourcePixelSize.width, expectedSourcePixelSize.height), 2_048)

        let preview = try ImageDecodeService().decode(
            url: url,
            format: .arw,
            purpose: .preview(maxPixelSize: 2_048)
        )

        XCTAssertLessThanOrEqual(max(preview.pixelSize.width, preview.pixelSize.height), 2_048)
        XCTAssertEqual(preview.sourcePixelSize, expectedSourcePixelSize)
        XCTAssertFalse(preview.isFullResolution)
        let luminanceRange = try XCTUnwrap(luminanceRange(in: preview.cgImage))
        XCTAssertGreaterThan(luminanceRange.maximum, luminanceRange.minimum + 4)
    }

    func testARWFixtureDirectoryCoversRepresentativeOrientationsWhenProvided() throws {
        guard let directoryPath = ProcessInfo.processInfo.environment["IMAGEVIEW_RAW_FIXTURE_DIRECTORY"],
              !directoryPath.isEmpty else {
            throw XCTSkip("Set IMAGEVIEW_RAW_FIXTURE_DIRECTORY to run the optional ARW orientation test")
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.caseInsensitiveCompare("arw") == .orderedSame }
        var fixtureByOrientation: [Int: (URL, CGSize)] = [:]
        for url in urls where fixtureByOrientation.count < 3 {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
                  [1, 6, 8].contains(orientation),
                  fixtureByOrientation[orientation] == nil,
                  let sourceSize = ImageDecodeService.orientedPixelSize(properties: properties) else {
                continue
            }
            fixtureByOrientation[orientation] = (url, sourceSize)
        }
        XCTAssertEqual(Set(fixtureByOrientation.keys), Set([1, 6, 8]))

        for orientation in [1, 6, 8] {
            let fixture = try XCTUnwrap(fixtureByOrientation[orientation])
            let preview = try ImageDecodeService().decode(
                url: fixture.0,
                format: .arw,
                purpose: .preview(maxPixelSize: 2_048)
            )
            XCTAssertEqual(preview.sourcePixelSize, fixture.1)
            XCTAssertEqual(
                preview.pixelSize.width > preview.pixelSize.height,
                fixture.1.width > fixture.1.height,
                "Unexpected preview aspect for EXIF orientation \(orientation)"
            )
            let range = try XCTUnwrap(luminanceRange(in: preview.cgImage))
            XCTAssertGreaterThan(range.maximum, range.minimum + 4)
        }
    }

    func testARWFixtureFullDecodeWhenProvided() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["IMAGEVIEW_RAW_FULL_FIXTURE"],
              !fixturePath.isEmpty else {
            throw XCTSkip("Set IMAGEVIEW_RAW_FULL_FIXTURE to run the optional full-resolution ARW test")
        }

        let url = URL(fileURLWithPath: fixturePath)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let expectedSourcePixelSize = try XCTUnwrap(ImageDecodeService.orientedPixelSize(properties: properties))
        let full = try ImageDecodeService().decode(url: url, format: .arw, purpose: .full)

        XCTAssertTrue(full.isFullResolution)
        XCTAssertEqual(full.pixelSize, expectedSourcePixelSize)
        XCTAssertEqual(full.sourcePixelSize, expectedSourcePixelSize)
        let range = try XCTUnwrap(luminanceRange(in: full.cgImage))
        XCTAssertGreaterThan(range.maximum, range.minimum + 4)
    }

    func testDecodedImageDefaultsSourceSemanticsForExistingCallers() throws {
        let image = try makeImage(width: 4, height: 3)

        let decoded = DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: 4, height: 3),
            isAnimated: false
        )

        XCTAssertEqual(decoded.sourcePixelSize, decoded.pixelSize)
        XCTAssertTrue(decoded.isFullResolution)
    }

    func testProgressivePreviewIsSkippedWhenOriginalFitsPreviewLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let smallURL = root.appendingPathComponent("small.png")
        let largeURL = root.appendingPathComponent("large.png")
        try makePNGData(width: 2_048, height: 2).write(to: smallURL)
        try makePNGData(width: 2_049, height: 2).write(to: largeURL)

        XCTAssertFalse(ImageDecodeService.requiresDownsampledPreview(url: smallURL, maxPixelSize: 2_048))
        XCTAssertTrue(ImageDecodeService.requiresDownsampledPreview(url: largeURL, maxPixelSize: 2_048))
    }

    func testDecodeMatchesImageIOPixelOrientationForEveryExifValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let markerImage = try makeOrientationMarkerImage(width: 80, height: 60)
        let samplePositions: [(CGFloat, CGFloat)] = [
            (0.25, 0.25),
            (0.75, 0.25),
            (0.25, 0.75),
            (0.75, 0.75)
        ]

        for orientation in 1...8 {
            let url = root.appendingPathComponent("orientation-\(orientation).jpg")
            try writeOrientedJPEG(markerImage, to: url, orientation: orientation)

            let decoded = try ImageDecodeService().decode(url: url, format: .jpeg)
            let expected = try imageIOOrientedImage(at: url)

            XCTAssertEqual(
                decoded.pixelSize,
                CGSize(width: expected.width, height: expected.height),
                "Unexpected dimensions for EXIF orientation \(orientation)"
            )
            XCTAssertEqual(
                decoded.sourcePixelSize,
                CGSize(width: expected.width, height: expected.height),
                "Unexpected source dimensions for EXIF orientation \(orientation)"
            )
            XCTAssertTrue(decoded.isFullResolution)

            for (xRatio, yRatio) in samplePositions {
                XCTAssertEqual(
                    sampledLuminance(in: decoded.cgImage, xRatio: xRatio, yRatio: yRatio),
                    sampledLuminance(in: expected, xRatio: xRatio, yRatio: yRatio),
                    "Unexpected pixel placement for EXIF orientation \(orientation) at \(xRatio), \(yRatio)"
                )
            }
        }
    }

    func testPreviewSourcePixelSizeAppliesExifOrientationBeforeDownsampling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let markerImage = try makeOrientationMarkerImage(width: 80, height: 60)

        for orientation in 1...8 {
            let url = root.appendingPathComponent("preview-orientation-\(orientation).jpg")
            try writeOrientedJPEG(markerImage, to: url, orientation: orientation)

            let decoded = try ImageDecodeService().decode(
                url: url,
                format: .jpeg,
                purpose: .preview(maxPixelSize: 40)
            )
            let swapsDimensions = (5...8).contains(orientation)
            let expectedSourceSize = swapsDimensions
                ? CGSize(width: 60, height: 80)
                : CGSize(width: 80, height: 60)
            let expectedPreviewSize = swapsDimensions
                ? CGSize(width: 30, height: 40)
                : CGSize(width: 40, height: 30)

            XCTAssertEqual(decoded.sourcePixelSize, expectedSourceSize)
            XCTAssertEqual(decoded.pixelSize, expectedPreviewSize)
            XCTAssertFalse(decoded.isFullResolution)
        }
    }

    func testDecodeSvgThroughSystemFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("icon.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16' fill='red'/></svg>"
        try svg.data(using: .utf8)!.write(to: url)

        let decoded = try ImageDecodeService().decode(url: url, format: .svg, maxPixelSize: 64)

        XCTAssertEqual(decoded.pixelSize.width, 16)
        XCTAssertEqual(decoded.pixelSize.height, 16)
        XCTAssertEqual(pixelColor(in: decoded.cgImage, x: 8, y: 8), .red)
    }

    func testComplexSVGIsFullyDecodedOrFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("complex.svg")
        let svg = """
        <svg width="24" height="12" viewBox="0 0 24 12">
          <rect x="1" y="2" width="8" height="8" fill="red"/>
          <rect x="15" y="2" width="8" height="8" fill="blue"/>
        </svg>
        <!-- malformed trailing markup intentionally exercises honest decoder failure
        """
        try XCTUnwrap(svg.data(using: .utf8)).write(to: url)

        do {
            let decoded = try ImageDecodeService().decode(url: url, format: .svg)
            XCTAssertTrue(pixelColor(in: decoded.cgImage, x: 4, y: 6)?.isPredominantlyRed == true)
            XCTAssertTrue(pixelColor(in: decoded.cgImage, x: 19, y: 6)?.isPredominantlyBlue == true)
        } catch ImageDecodeError.cannotDecodeImage {
            // An honest failure is preferable to a partial image.
        } catch {
            XCTFail("Unexpected SVG decode error: \(error)")
        }
    }

    func testRequiredRasterFormatsHaveSystemDecoderRegistration() throws {
        let sourceTypes = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
        let formats: [SupportedImageFormat] = [.jpeg, .png, .gif, .tiff, .bmp, .heic, .heif, .webp, .avif]

        for format in formats {
            let identifier = try XCTUnwrap(format.imageIOTypeIdentifier, "Missing ImageIO type for \(format)")
            XCTAssertTrue(sourceTypes.contains(identifier), "ImageIO has no decoder registered for \(identifier)")
        }
    }

    func testDecodeGeneratedSystemWritableRequiredFormats() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let formats: [(SupportedImageFormat, String)] = [
            (.jpeg, "jpg"), (.png, "png"), (.gif, "gif"), (.tiff, "tiff"), (.bmp, "bmp")
        ]
        let image = try makeImage(width: 4, height: 3)
        let writableTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

        for (format, fileExtension) in formats {
            let type = try XCTUnwrap(format.contentType?.identifier)
            XCTAssertTrue(writableTypes.contains(type), "ImageIO cannot generate \(type) for this regression test")
            let url = root.appendingPathComponent("sample.\(fileExtension)")
            do {
                try write(image, to: url, type: type)
            } catch {
                XCTFail("ImageIO could not generate \(type): \(error)")
                continue
            }

            let decoded = try ImageDecodeService().decode(url: url, format: format)
            XCTAssertEqual(decoded.pixelSize, CGSize(width: 4, height: 3), "Failed for \(format)")
        }
    }

    func testDecodeAnimatedGifReturnsFramesAndDelays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("animated.gif")
        try writeAnimatedGIF(to: url)

        let decoded = try ImageDecodeService().decode(url: url, format: .gif)

        XCTAssertTrue(decoded.isAnimated)
        XCTAssertEqual(decoded.animationFrames.count, 2)
        XCTAssertEqual(decoded.animationFrames.map(\.duration), [0.1, 0.2])
    }

    func testDecodedByteCostIncludesMainImageAndEveryAnimationFrame() throws {
        let main = try makeImage(width: 4, height: 3)
        let firstFrame = try makeImage(width: 2, height: 2)
        let secondFrame = try makeImage(width: 3, height: 1)
        let decoded = DecodedImage(
            cgImage: main,
            pixelSize: CGSize(width: main.width, height: main.height),
            isAnimated: true,
            animationFrames: [
                AnimatedFrame(cgImage: firstFrame, duration: 0.1),
                AnimatedFrame(cgImage: secondFrame, duration: 0.2)
            ]
        )
        let expectedMainCost = main.bytesPerRow * main.height
        let expectedFrameCosts = [firstFrame, secondFrame]
            .reduce(0) { $0 + ($1.bytesPerRow * $1.height) }

        XCTAssertEqual(decoded.decodedByteCost, expectedMainCost + expectedFrameCosts)
    }

    func testDecodedByteCostSaturatesOnOverflow() {
        XCTAssertEqual(
            DecodedImage.saturatedByteCost(bytesPerRow: Int.max, height: 2),
            Int.max
        )
        XCTAssertEqual(DecodedImage.saturatedSum(Int.max, 1), Int.max)
    }

    func testDecodeAnimatedGifAboveAnimationBudgetReturnsVisibleFirstFrameWithoutFrames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("limited.gif")
        try writeAnimatedGIF(to: url)

        let limited = try ImageDecodeService(animationByteLimit: 1).decode(url: url, format: .gif)

        XCTAssertEqual(limited.pixelSize, CGSize(width: 4, height: 3))
        XCTAssertTrue(limited.isAnimated)
        XCTAssertTrue(limited.animationFrames.isEmpty)
        XCTAssertGreaterThan(limited.decodedByteCost, 0)
    }

    func testDecodeAnimatedGifKeepsOnlyFullResolutionFirstFrameEagerWhenAnimationExceedsBudget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("streamed-animation.gif")
        try writeAnimatedGIF(to: url)

        let decoded = try ImageDecodeService(animationByteLimit: 64)
            .decode(url: url, format: .gif)

        XCTAssertTrue(decoded.isAnimated)
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 4, height: 3))
        XCTAssertTrue(decoded.animationFrames.isEmpty)
        let frameSource = try XCTUnwrap(decoded.animationFrameSource)
        XCTAssertEqual(frameSource.frameCount, 2)
        let secondFrame = try XCTUnwrap(frameSource.frame(at: 1))
        XCTAssertEqual(
            CGSize(width: secondFrame.cgImage.width, height: secondFrame.cgImage.height),
            CGSize(width: 4, height: 3)
        )
        XCTAssertEqual(secondFrame.duration, 0.2)
    }

    func testAnimationBudgetAllowsExactEstimateAndKeepsOneByteLessOutOfEagerFrames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("boundary.gif")
        try writeAnimatedGIF(to: url)
        let estimatedFrameCost = 4 * 3 * 4 * 2

        let atLimit = try ImageDecodeService(animationByteLimit: estimatedFrameCost)
            .decode(url: url, format: .gif)
        let belowLimit = try ImageDecodeService(animationByteLimit: estimatedFrameCost - 1)
            .decode(url: url, format: .gif)

        XCTAssertEqual(atLimit.animationFrames.count, 2)
        XCTAssertTrue(atLimit.animationFrames.allSatisfy { max($0.cgImage.width, $0.cgImage.height) == 4 })
        XCTAssertTrue(belowLimit.animationFrames.isEmpty)
        XCTAssertNil(atLimit.animationFrameSource)
        XCTAssertEqual(belowLimit.animationFrameSource?.frameCount, 2)
    }

    func testAnimationEstimateRejectsMissingPropertiesAndOverflow() {
        XCTAssertNil(ImageDecodeService.estimatedAnimationByteCost(frameDimensions: [(nil, 3)]))
        XCTAssertNil(ImageDecodeService.estimatedAnimationByteCost(frameDimensions: [(4, nil)]))
        XCTAssertNil(ImageDecodeService.estimatedAnimationByteCost(frameDimensions: [(Int.max, 2)]))
    }

    func testDecodeEmbeddedWebPSample() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.webp")
        let data = try XCTUnwrap(Data(base64Encoded: "UklGRiIAAABXRUJQVlA4IBYAAADQAQCdASoBAAEAAUAmJaQAA3AA/vuUAAA="))
        try data.write(to: url)

        let decoded = try ImageDecodeService().decode(url: url, format: .webp)

        XCTAssertEqual(decoded.pixelSize, CGSize(width: 1, height: 1))
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        let image = try makeImage(width: width, height: height)
        guard let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }

        return destinationData as Data
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.cannotCreateContext
        }

        context.setFillColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestError.cannotCreateContext
        }
        return image
    }

    private func makeOrientationMarkerImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw TestError.cannotCreateContext
        }

        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        let quadrants: [(CGFloat, CGRect)] = [
            (0.1, CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)),
            (0.35, CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)),
            (0.65, CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)),
            (0.9, CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight))
        ]
        for (gray, rect) in quadrants {
            context.setFillColor(gray: gray, alpha: 1)
            context.fill(rect)
        }

        guard let image = context.makeImage() else {
            throw TestError.cannotCreateContext
        }
        return image
    }

    private func write(_ image: CGImage, to url: URL, type: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
    }

    private func writeOrientedJPEG(_ image: CGImage, to url: URL, orientation: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1.0
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
    }

    private func imageIOOrientedImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: max(width, height)
                  ] as CFDictionary
              ) else {
            throw TestError.cannotDecodeImage
        }
        return image
    }

    private func sampledLuminance(in image: CGImage, xRatio: CGFloat, yRatio: CGFloat) -> UInt8? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        let x = min(image.width - 1, max(0, Int(CGFloat(image.width) * xRatio)))
        let y = min(image.height - 1, max(0, Int(CGFloat(image.height) * yRatio)))
        return data[(y * image.width) + x]
    }

    private func luminanceRange(in image: CGImage) -> (minimum: Int, maximum: Int)? {
        let width = 32
        let height = 32
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        var minimum = 255
        var maximum = 0
        for index in 0..<(width * height) {
            let value = Int(data[index])
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        return (minimum, maximum)
    }

    private func writeAnimatedGIF(to url: URL) throws {
        let first = try makeImage(width: 4, height: 3)
        let second = try makeImage(width: 4, height: 3)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil) else {
            throw TestError.cannotEncodeImage
        }
        let firstProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        let secondProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary
        CGImageDestinationAddImage(destination, first, firstProperties)
        CGImageDestinationAddImage(destination, second, secondProperties)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
    }

    private enum TestError: Error {
        case cannotCreateContext
        case cannotEncodeImage
        case cannotDecodeImage
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) -> RGBA? {
        guard let provider = image.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = (y * image.bytesPerRow) + (x * bytesPerPixel)
        guard bytesPerPixel >= 4 else {
            return nil
        }

        return RGBA(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }

    private struct RGBA: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)

        var isPredominantlyRed: Bool {
            alpha > 200 && red > 200 && Int(red) > Int(green) * 2 && Int(red) > Int(blue) * 2
        }

        var isPredominantlyBlue: Bool {
            alpha > 200 && blue > 200 && Int(blue) > Int(red) * 2 && Int(blue) > Int(green) * 2
        }
    }
}
