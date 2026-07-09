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
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
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

        guard let image = context.makeImage(),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }

        return destinationData as Data
    }

    private enum TestError: Error {
        case cannotCreateContext
        case cannotEncodeImage
    }
}
