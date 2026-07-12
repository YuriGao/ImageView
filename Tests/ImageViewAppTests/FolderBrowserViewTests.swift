import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FolderBrowserViewTests: XCTestCase {
    func testExposesToolbarControls() {
        let view = FolderBrowserView(thumbnailProvider: .stub)

        XCTAssertEqual(view.testingSearchPlaceholder, "Search images")
        XCTAssertTrue(view.testingHasSortControl)
        XCTAssertTrue(view.testingHasTypeFilterControl)
        XCTAssertTrue(view.testingHasTrashButton)
        XCTAssertTrue(view.testingHasMoveButton)
        XCTAssertTrue(view.testingHasRenameButton)
        XCTAssertTrue(view.testingHasCollectionView)
    }

    func testApplyUpdatesItemCountAndSelectedIDs() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.jpg"), format: .jpeg)
        let view = FolderBrowserView(thumbnailProvider: .stub)

        view.apply(items: [first, second], selectedIDs: [second.id])

        XCTAssertEqual(view.testingItemCount, 2)
        XCTAssertEqual(view.testingSelectedIDs, [second.id])
    }

    func testSelectingItemInvokesSelectionCallback() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.jpg"), format: .jpeg)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var selectedIDs: Set<ImageItem.ID>?
        view.onSelectionChanged = { selectedIDs = $0 }
        view.apply(items: [first, second], selectedIDs: [])

        view.testingSelectItems(with: [first.id])

        XCTAssertEqual(selectedIDs, [first.id])
        XCTAssertEqual(view.testingSelectedIDs, [first.id])
    }

    func testOpenActionInvokesOpenCallbackForSelectedItem() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/open.png"), format: .png)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var openedItem: ImageItem?
        view.onOpenItem = { openedItem = $0 }
        view.apply(items: [item], selectedIDs: [])

        view.testingSelectItems(with: [item.id])
        view.testingPerformOpenAction()

        XCTAssertEqual(openedItem, item)
    }

    func testToolbarCallbacks() {
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var searchText: String?
        var sortMode: FolderSortMode?
        var typeFilter: Set<SupportedImageFormat>?
        var didTrash = false
        var didMove = false
        var didRename = false
        view.onSearchChanged = { searchText = $0 }
        view.onSortChanged = { sortMode = $0 }
        view.onTypeFilterChanged = { typeFilter = $0 }
        view.onMoveToTrash = { didTrash = true }
        view.onMoveToFolder = { didMove = true }
        view.onBatchRename = { didRename = true }

        view.testingSetSearchText("cat")
        view.testingSetSortMode(.fileSizeDescending)
        view.testingSelectTypeFilterPopupItem(.png)
        view.testingTriggerTrash()
        view.testingTriggerMove()
        view.testingTriggerRename()

        XCTAssertEqual(searchText, "cat")
        XCTAssertEqual(sortMode, .fileSizeDescending)
        XCTAssertEqual(typeFilter, [.png])
        XCTAssertTrue(didTrash)
        XCTAssertTrue(didMove)
        XCTAssertTrue(didRename)
    }

    func testAllTypesFilterPopupSelectionInvokesTypeFilterCallback() {
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var typeFilter: Set<SupportedImageFormat>?
        view.onTypeFilterChanged = { typeFilter = $0 }

        view.testingSelectAllTypesFilterPopupItem()

        XCTAssertEqual(typeFilter, Set(SupportedImageFormat.allCases))
    }
}

private extension ThumbnailProvider {
    static var stub: ThumbnailProvider {
        ThumbnailProvider(loader: { _, _, completion in
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })
    }
}
