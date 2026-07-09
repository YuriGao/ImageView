import XCTest
@testable import ImageViewCore

final class SupportedImageFormatTests: XCTestCase {
    func testRequiredExtensionsAreSupported() {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "avif", "svg"]
        for ext in extensions {
            XCTAssertNotNil(SupportedImageFormat(fileExtension: ext), ext)
        }
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(SupportedImageFormat(fileExtension: "txt"))
    }
}
