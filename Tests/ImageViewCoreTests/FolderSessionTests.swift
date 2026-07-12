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

    func testLastOpenedItemSurvivesRemovingAndReplacingOtherItems() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let opened = ImageItem(url: folder.appendingPathComponent("opened.png"), format: .png)
        let other = ImageItem(url: folder.appendingPathComponent("other.png"), format: .png)
        let replacement = ImageItem(url: folder.appendingPathComponent("replacement.png"), format: .png)
        var session = FolderSession(
            folderURL: folder,
            items: [opened, other]
        )

        session.recordOpenedItem(with: opened.id)

        session.removeItems(with: [other.id])
        XCTAssertEqual(session.lastOpenedItemID, opened.id)

        session.replaceItems([replacement, opened])
        XCTAssertEqual(session.lastOpenedItemID, opened.id)
    }

    func testLastOpenedItemClearsWhenOpenedItemIsRemovedOrReplacedAway() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let opened = ImageItem(url: folder.appendingPathComponent("opened.png"), format: .png)
        var removedSession = FolderSession(
            folderURL: folder,
            items: [opened],
            lastOpenedItemID: opened.id
        )
        var replacedSession = removedSession

        removedSession.removeItems(with: [opened.id])
        replacedSession.replaceItems([])

        XCTAssertNil(removedSession.lastOpenedItemID)
        XCTAssertNil(replacedSession.lastOpenedItemID)
    }
}
