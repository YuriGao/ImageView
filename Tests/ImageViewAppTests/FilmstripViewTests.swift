import Foundation
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FilmstripViewTests: XCTestCase {
    func testApplyBuildsButtonsAndSelectionCallsOnSelect() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/b.png"), format: .png)
        let filmstrip = FilmstripView()
        let expectation = expectation(description: "select")
        var selected: ImageItem?

        filmstrip.onSelect = { item in
            selected = item
            expectation.fulfill()
        }

        filmstrip.apply(items: [first, second], current: second)

        let buttons = filmstrip.debugButtons()
        XCTAssertEqual(buttons.map(\.title), ["a", "b"])
        XCTAssertEqual(buttons[1].contentTintColor, .controlAccentColor)

        filmstrip.performDebugSelection(buttons[0])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(selected?.url, first.url)
        XCTAssertEqual(selected?.format, .png)
    }
}
