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
}
