import XCTest
@testable import ImageViewCore

final class SupportedImageFormatTests: XCTestCase {
    func testRequiredExtensionsAreSupported() {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "avif", "svg", "arw"]
        for ext in extensions {
            XCTAssertNotNil(SupportedImageFormat(fileExtension: ext), ext)
        }
    }

    func testSonyARWUsesImportedReadOnlyType() {
        XCTAssertEqual(SupportedImageFormat(fileExtension: ".ARW"), .arw)
        XCTAssertEqual(SupportedImageFormat.arw.contentType?.identifier, "com.sony.arw-raw-image")
        XCTAssertEqual(SupportedImageFormat.arw.imageIOTypeIdentifier, "com.sony.arw-raw-image")
        XCTAssertFalse(SupportedImageFormat.arw.canAttemptSafeWrite)
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(SupportedImageFormat(fileExtension: "txt"))
    }
}
