import Foundation
import XCTest
@testable import ImageViewCore

final class FolderSessionTests: XCTestCase {
    func testVisibleItemsAppliesSearchFormatFilterAndNameSort() {
        let folder = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        let items = [
            ImageItem(url: folder.appendingPathComponent("b.PNG"), format: .png),
            ImageItem(url: folder.appendingPathComponent("a.jpg"), format: .jpeg),
            ImageItem(url: folder.appendingPathComponent("a-web.webp"), format: .webp)
        ]
        let filter = FolderFilter(searchText: "a", allowedFormats: [.jpeg, .webp])
        let session = FolderSession(
            folderURL: folder,
            items: items,
            filter: filter,
            sortMode: .nameAscending
        )

        XCTAssertEqual(session.visibleItems.map(\.url.lastPathComponent), ["a-web.webp", "a.jpg"])
    }

    func testSelectionIsTrimmedWhenFilterHidesSelectedItems() {
        let folder = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        let png = ImageItem(url: folder.appendingPathComponent("b.png"), format: .png)
        let jpeg = ImageItem(url: folder.appendingPathComponent("a.jpg"), format: .jpeg)
        var session = FolderSession(
            folderURL: folder,
            items: [png, jpeg],
            selectedItemIDs: [png.id, jpeg.id]
        )

        session.filter = FolderFilter(allowedFormats: [.png])

        XCTAssertEqual(session.selectedItemIDs, [png.id])
        XCTAssertEqual(session.selectedItems, [png])
    }
}
