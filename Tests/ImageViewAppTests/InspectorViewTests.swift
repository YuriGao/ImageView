import XCTest
@testable import ImageViewApp

@MainActor
final class InspectorViewTests: XCTestCase {
    func testUnknownMetadataFormattingFallbacksAreExplicit() {
        let expected = AppStrings.text("inspector.unknown")
        XCTAssertEqual(InspectorView.fileSizeText(nil), expected)
        XCTAssertEqual(InspectorView.dateText(nil), expected)
    }

    func testFileSizeFormattingUsesReadableUnits() {
        let text = InspectorView.fileSizeText(1_024)
        XCTAssertTrue(text.contains("1"))
        XCTAssertTrue(text.contains("KB"))
    }
}
