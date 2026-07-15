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

    func testExposureFormattingUsesPhotographyNotation() {
        XCTAssertEqual(InspectorView.exposureTimeText(1.0 / 125.0), "1/125 s")
        XCTAssertEqual(InspectorView.exposureTimeText(2), "2.00 s")
    }
}
