import XCTest
@testable import ImageViewCore

final class NavigationStateTests: XCTestCase {
    func testStartsAtOpenedFileAndMoves() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "b.png")
        state.moveNext()
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "c.png")
        state.movePrevious()
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "b.png")
    }

    func testRemoveCurrentKeepsNearestUsableItem() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        state.removeCurrent()

        XCTAssertEqual(state.items.map { $0.url.lastPathComponent }, ["a.png", "c.png"])
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "c.png")
    }

    func testReplaceCurrentURLResortsSequence() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        state.replaceCurrentURL(URL(fileURLWithPath: "/tmp/d.png"), format: .png)

        XCTAssertEqual(state.items.map { $0.url.lastPathComponent }, ["a.png", "c.png", "d.png"])
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "d.png")
    }

    private func makeItems(_ names: [String]) -> [ImageItem] {
        names.map { ImageItem(url: URL(fileURLWithPath: "/tmp/\($0)"), format: .png) }
    }
}
