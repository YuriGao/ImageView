import CoreGraphics
import Foundation
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
