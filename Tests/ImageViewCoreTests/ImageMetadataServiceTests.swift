import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewCore

final class ImageMetadataServiceTests: XCTestCase {
    func testMetadataIncludesFormatPixelsFileSizeAndModificationDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("sample.png")
        let data = Data([0, 1, 2, 3, 4, 5])
        try data.write(to: url)
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)

        let metadata = ImageMetadataService().metadata(
            for: url,
            format: .png,
            pixelWidth: 640,
            pixelHeight: 480
        )

        XCTAssertEqual(metadata.url, url)
        XCTAssertEqual(metadata.format, .png)
        XCTAssertEqual(metadata.pixelWidth, 640)
        XCTAssertEqual(metadata.pixelHeight, 480)
        XCTAssertEqual(metadata.fileSize, Int64(data.count))
        XCTAssertEqual(metadata.modifiedAt, modifiedAt)
    }

    func testMetadataReadsBasicExifCameraAndCaptureDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("camera.jpg")
        try writeJPEGWithExif(to: url)

        let metadata = ImageMetadataService().metadata(for: url, format: .jpeg, pixelWidth: 2, pixelHeight: 2)

        XCTAssertEqual(metadata.cameraMake, "ImageView")
        XCTAssertEqual(metadata.cameraModel, "Test Camera")
        XCTAssertEqual(metadata.capturedAt, DateFormatter.exif.date(from: "2026:07:10 12:34:56"))
    }

    private func writeJPEGWithExif(to url: URL) throws {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TestError.cannotCreateImage
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "ImageView",
                kCGImagePropertyTIFFModel: "Test Camera"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:10 12:34:56"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TestError.cannotCreateImage }
    }

    private enum TestError: Error { case cannotCreateImage }
}

private extension DateFormatter {
    static let exif: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}
