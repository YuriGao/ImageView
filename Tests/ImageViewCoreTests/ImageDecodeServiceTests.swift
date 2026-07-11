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
        XCTAssertFalse(decoded.isAnimated)
    }

    func testDecodeAppliesExifOrientationForFullResolutionImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("oriented.jpg")
        try writeOrientedJPEG(to: url, width: 4, height: 3)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(
            (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue
                ?? (tiff?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue,
            6
        )

        let decoded = try ImageDecodeService().decode(url: url, format: .jpeg)

        XCTAssertEqual(decoded.pixelSize, CGSize(width: 3, height: 4))
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

    func testAnimationBudgetAllowsExactEstimateAndRejectsOneByteLess() throws {
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
        XCTAssertTrue(belowLimit.animationFrames.isEmpty)
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

    private func write(_ image: CGImage, to url: URL, type: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
    }

    private func writeOrientedJPEG(to url: URL, width: Int, height: Int) throws {
        let image = try makeImage(width: width, height: height)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
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
    }
}
