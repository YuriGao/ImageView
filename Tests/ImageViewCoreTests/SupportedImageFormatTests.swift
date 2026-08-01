import XCTest
@testable import ImageViewCore

final class SupportedImageFormatTests: XCTestCase {
    func testRequiredExtensionsAreSupported() {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "avif", "svg", "arw", "nef"]
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

    func testNikonNEFUsesImportedReadOnlyType() {
        XCTAssertEqual(SupportedImageFormat(fileExtension: ".NEF"), .nef)
        XCTAssertEqual(SupportedImageFormat.nef.contentType?.identifier, "com.nikon.raw-image")
        XCTAssertEqual(SupportedImageFormat.nef.imageIOTypeIdentifier, "com.nikon.raw-image")
        XCTAssertFalse(SupportedImageFormat.nef.canAttemptSafeWrite)
        XCTAssertTrue(SupportedImageFormat.nef.isCameraRAW)
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(SupportedImageFormat(fileExtension: "txt"))
    }
}
