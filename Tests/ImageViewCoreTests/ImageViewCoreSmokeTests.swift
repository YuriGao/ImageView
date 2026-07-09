import XCTest
@testable import ImageViewCore

final class ImageViewCoreSmokeTests: XCTestCase {
    func testCoreVersionIsAvailable() {
        XCTAssertEqual(ImageViewCoreVersion.current, "0.1.0")
    }
}
