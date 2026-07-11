import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewCore

final class ImageEditingServiceTests: XCTestCase {
    func testHorizontalMirrorReversesPixelsLeftToRight() throws {
        let image = try makeImage(rows: [
            [.red, .green, .blue],
            [.yellow, .magenta, .cyan]
        ])

        let result = try ImageEditingService().apply([.mirrorHorizontal], to: image)

        XCTAssertEqual(try pixelRows(in: result), [
            [.blue, .green, .red],
            [.cyan, .magenta, .yellow]
        ])
    }

    func testCropUsesExpectedPixelOrigin() throws {
        let image = try makeImage(rows: [
            [.red, .green, .blue],
            [.yellow, .magenta, .cyan]
        ])

        let result = try ImageEditingService().apply([.crop(CGRect(x: 1, y: 0, width: 2, height: 1))], to: image)

        XCTAssertEqual(try pixelRows(in: result), [[.green, .blue]])
    }

    func testCropProducesRequestedDimensions() throws {
        let image = try makeImage(rows: [
            [.red, .green, .blue, .yellow, .magenta],
            [.cyan, .red, .green, .blue, .yellow],
            [.magenta, .cyan, .red, .green, .blue],
            [.yellow, .magenta, .cyan, .red, .green]
        ])

        let result = try ImageEditingService().apply(
            [.crop(CGRect(x: 1, y: 1, width: 3, height: 2))],
            to: image
        )

        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 2)
    }

    func testRotateClockwiseMovesPixelsIntoClockwiseOrientation() throws {
        let image = try makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
            [.magenta, .cyan]
        ])

        let result = try ImageEditingService().apply([.rotateClockwise], to: image)

        XCTAssertEqual(try pixelRows(in: result), [
            [.magenta, .blue, .red],
            [.cyan, .yellow, .green]
        ])
    }

    func testUnsupportedSaveFormatThrows() throws {
        let image = try makeImage(rows: [[.red, .green], [.blue, .yellow]])

        XCTAssertThrowsError(
            try ImageEditingService().save(
                image,
                to: URL(fileURLWithPath: "/tmp/a.svg"),
                format: .svg
            )
        )
    }

    func testWritableSaveFormatsIncludePortableFormatsAndExcludeUnsupportedFormats() {
        let formats = ImageEditingService.writableSaveFormats()

        XCTAssertTrue(formats.contains(.png))
        XCTAssertTrue(formats.contains(.jpeg))
        XCTAssertTrue(formats.contains(.tiff))
        XCTAssertTrue(formats.contains(.bmp))
        XCTAssertFalse(formats.contains(.gif))
        XCTAssertFalse(formats.contains(.webp))
        XCTAssertFalse(formats.contains(.avif))
        XCTAssertFalse(formats.contains(.svg))
    }

    func testHEIFSaveThrowsWhenNoHEIFDestinationWriterExists() throws {
        let image = try makeImage(rows: [[.red]])
        let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard !destinationTypes.contains(SupportedImageFormat.heif.contentType?.identifier ?? "") else {
            throw XCTSkip("Current platform exposes HEIF writing support.")
        }

        XCTAssertThrowsError(
            try ImageEditingService().save(
                image,
                to: URL(fileURLWithPath: "/tmp/a.heif"),
                format: .heif
            )
        ) { error in
            XCTAssertEqual(error as? ImageEditingError, .unsupportedSaveFormat)
        }
    }

    func testSavePreservesCompatibleMetadataAndNormalizesOrientation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("metadata-source.jpg")
        let outputURL = root.appendingPathComponent("metadata-output.jpg")
        try makeMetadataJPEG().write(to: sourceURL)
        let decoded = try ImageDecodeService().decode(url: sourceURL, format: .jpeg)
        let output = try ImageEditingService().apply([.mirrorHorizontal], to: decoded.cgImage)

        try ImageEditingService().save(
            output,
            to: outputURL,
            format: .jpeg,
            metadataSourceURL: sourceURL
        )

        let properties = try imageProperties(at: outputURL)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:07:11 12:34:56")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFMake] as? String, "ImageView Test")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFModel] as? String, "Metadata Fixture")
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 144)
        XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.intValue, 144)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, output.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, output.height)
    }

    private func makeImage(rows: [[Pixel]]) throws -> CGImage {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            throw TestError.invalidImageData
        }

        let width = firstRow.count
        let height = rows.count
        guard rows.allSatisfy({ $0.count == width }) else {
            throw TestError.invalidImageData
        }

        let bytes = rows.flatMap { row in
            row.flatMap(\.rgba)
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw TestError.invalidImageData
        }

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw TestError.invalidImageData
        }

        return image
    }

    private func makeMetadataJPEG() throws -> Data {
        let image = try makeImage(rows: [
            [.red, .green, .blue, .yellow],
            [.magenta, .cyan, .red, .green]
        ])
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw TestError.invalidImageData
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyDPIWidth: 144,
            kCGImagePropertyDPIHeight: 144,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:11 12:34:56"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "ImageView Test",
                kCGImagePropertyTIFFModel: "Metadata Fixture",
                kCGImagePropertyTIFFOrientation: 6
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLatitude: 31.2304,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSLongitude: 121.4737
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.invalidImageData
        }
        return data as Data
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TestError.invalidImageData
        }
        return properties
    }

    private func pixelRows(in image: CGImage) throws -> [[Pixel]] {
        guard let provider = image.dataProvider,
              let data = provider.data else {
            throw TestError.invalidImageData
        }

        let bytes = CFDataGetBytePtr(data)!
        return (0..<image.height).map { row in
            (0..<image.width).map { column in
                let offset = row * image.bytesPerRow + column * 4
                return Pixel(
                    red: bytes[offset],
                    green: bytes[offset + 1],
                    blue: bytes[offset + 2],
                    alpha: bytes[offset + 3]
                )
            }
        }
    }

    private struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        var rgba: [UInt8] { [red, green, blue, alpha] }

        static let red = Pixel(red: 255, green: 0, blue: 0, alpha: 255)
        static let green = Pixel(red: 0, green: 255, blue: 0, alpha: 255)
        static let blue = Pixel(red: 0, green: 0, blue: 255, alpha: 255)
        static let yellow = Pixel(red: 255, green: 255, blue: 0, alpha: 255)
        static let magenta = Pixel(red: 255, green: 0, blue: 255, alpha: 255)
        static let cyan = Pixel(red: 0, green: 255, blue: 255, alpha: 255)
    }

    private enum TestError: Error {
        case invalidImageData
    }
}
