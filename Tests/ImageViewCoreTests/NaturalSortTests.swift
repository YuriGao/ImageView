import XCTest
@testable import ImageViewCore

final class NaturalSortTests: XCTestCase {
    func testSortsNumbersNaturally() {
        let names = ["image-10.png", "image-2.png", "image-1.png"]
        XCTAssertEqual(names.sorted(by: NaturalSort.compare), ["image-1.png", "image-2.png", "image-10.png"])
    }
}
