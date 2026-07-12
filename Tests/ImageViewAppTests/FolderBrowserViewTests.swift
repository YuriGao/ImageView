import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FolderBrowserViewTests: XCTestCase {
    func testExposesToolbarControls() {
        let view = FolderBrowserView(thumbnailProvider: .stub)

        XCTAssertEqual(view.testingSearchPlaceholder, AppStrings.text("folderBrowser.searchPlaceholder"))
        XCTAssertTrue(view.testingHasSortControl)
        XCTAssertTrue(view.testingHasTypeFilterControl)
        XCTAssertTrue(view.testingHasTrashButton)
        XCTAssertTrue(view.testingHasMoveButton)
        XCTAssertTrue(view.testingHasRenameButton)
        XCTAssertTrue(view.testingHasCollectionView)
        XCTAssertEqual(view.testingTrashButtonTitle, AppStrings.text("folderBrowser.button.trash"))
        XCTAssertEqual(view.testingMoveButtonTitle, AppStrings.text("folderBrowser.button.move"))
        XCTAssertEqual(view.testingRenameButtonTitle, AppStrings.text("folderBrowser.button.rename"))
    }

    func testApplyUpdatesItemCountAndSelectedIDs() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.jpg"), format: .jpeg)
        let view = FolderBrowserView(thumbnailProvider: .stub)

        view.apply(items: [first, second], selectedIDs: [second.id])

        XCTAssertEqual(view.testingItemCount, 2)
        XCTAssertEqual(view.testingSelectedIDs, [second.id])
    }

    func testSelectionOnlyUpdateDoesNotRestartThumbnailRequests() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/one.png"), format: .png)
        let loadCount = FolderBrowserLockedValue(0)
        let provider = ThumbnailProvider(loader: { _, _, completion in
            loadCount.withValue { $0 += 1 }
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })
        let view = FolderBrowserView(thumbnailProvider: provider)
        view.applyItems([item])
        _ = view.testingCell(at: 0)

        view.applySelection([item.id])

        XCTAssertEqual(loadCount.value, 1)
        XCTAssertEqual(view.testingSelectedIDs, [item.id])
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

    func testOperationStatusDisplaysMessageFailureCountAndOperatingState() {
        let view = FolderBrowserView(thumbnailProvider: .stub)
        let failedURL = URL(fileURLWithPath: "/tmp/photos/blocked.png")

        view.applyOperationStatus(
            message: "1 succeeded, 1 failed",
            failures: [BatchFileFailure(url: failedURL, reason: .destinationExists)],
            isOperating: true
        )

        XCTAssertEqual(
            view.testingOperationStatusText,
            "\(AppStrings.text("folderBrowser.status.working")) 1 succeeded, 1 failed · " +
            "\(String(format: AppStrings.text("folderBrowser.status.failure.one"), 1)) · " +
            "blocked.png: \(AppStrings.text("folderBrowser.failure.destinationExists"))"
        )
        XCTAssertTrue(view.testingBatchActionButtonsDisabled)
    }
}

private final class FolderBrowserLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storedValue) }
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
