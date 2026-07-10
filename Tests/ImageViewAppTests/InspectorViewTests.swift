import XCTest
@testable import ImageViewApp

@MainActor
final class InspectorViewTests: XCTestCase {
    func testUnknownMetadataFormattingFallbacksAreExplicit() {
        XCTAssertEqual(InspectorView.fileSizeText(nil), "Unknown")
        XCTAssertEqual(InspectorView.dateText(nil), "Unknown")
    }

    func testFileSizeFormattingUsesReadableUnits() {
        let text = InspectorView.fileSizeText(1_024)
        XCTAssertTrue(text.contains("1"))
        XCTAssertTrue(text.contains("KB"))
    }
}
