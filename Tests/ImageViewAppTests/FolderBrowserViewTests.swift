import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FolderBrowserViewTests: XCTestCase {
    func testPresentationStatesShowCopyRecoveryActionsAndInvokeCallbacks() {
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var clearedFilters = false
        var retriedFolder = false
        var choseAnotherFolder = false
        view.onClearFilters = { clearedFilters = true }
        view.onRetryFolder = { retriedFolder = true }
        view.onChooseAnotherFolder = { choseAnotherFolder = true }

        view.applyPresentation(.loading)
        XCTAssertTrue(view.testingHasSortControl, "The toolbar must remain mounted outside content state")
        XCTAssertTrue(view.testingHasTypeFilterControl, "The toolbar must remain mounted outside content state")
        XCTAssertTrue(view.testingHasTrashButton, "The toolbar must remain mounted outside content state")
        XCTAssertEqual(view.testingPresentationTitle, AppStrings.text("folderBrowser.state.loading.title"))
        XCTAssertEqual(view.testingPresentationMessage, AppStrings.text("folderBrowser.state.loading.message"))
        XCTAssertTrue(view.testingIsProgressVisible)
        XCTAssertEqual(view.testingVisibleRecoveryButtonTitles, [])
        XCTAssertFalse(view.testingIsCollectionVisible)

        view.applyPresentation(.emptyFolder)
        XCTAssertEqual(view.testingPresentationTitle, AppStrings.text("folderBrowser.state.emptyFolder.title"))
        XCTAssertEqual(view.testingPresentationMessage, AppStrings.text("folderBrowser.state.emptyFolder.message"))
        XCTAssertFalse(view.testingIsProgressVisible)
        XCTAssertEqual(
            view.testingVisibleRecoveryButtonTitles,
            [AppStrings.text("folderBrowser.button.chooseAnotherFolder")]
        )
        view.testingTriggerPrimaryRecovery()
        XCTAssertTrue(choseAnotherFolder)

        view.applyPresentation(.filteredEmpty)
        XCTAssertEqual(view.testingPresentationTitle, AppStrings.text("folderBrowser.state.filteredEmpty.title"))
        XCTAssertEqual(view.testingPresentationMessage, AppStrings.text("folderBrowser.state.filteredEmpty.message"))
        XCTAssertEqual(
            view.testingVisibleRecoveryButtonTitles,
            [AppStrings.text("folderBrowser.button.clearFilters")]
        )
        view.testingTriggerPrimaryRecovery()
        XCTAssertTrue(clearedFilters)

        choseAnotherFolder = false
        view.applyPresentation(.loadFailed("Permission denied"))
        XCTAssertEqual(view.testingPresentationTitle, AppStrings.text("folderBrowser.state.loadFailed.title"))
        XCTAssertEqual(view.testingPresentationMessage, "Permission denied")
        XCTAssertEqual(
            view.testingVisibleRecoveryButtonTitles,
            [
                AppStrings.text("folderBrowser.button.retry"),
                AppStrings.text("folderBrowser.button.chooseAnotherFolder")
            ]
        )
        view.testingTriggerPrimaryRecovery()
        view.testingTriggerSecondaryRecovery()
        XCTAssertTrue(retriedFolder)
        XCTAssertTrue(choseAnotherFolder)

        view.applyPresentation(.content)
        XCTAssertNil(view.testingPresentationTitle)
        XCTAssertNil(view.testingPresentationMessage)
        XCTAssertEqual(view.testingVisibleRecoveryButtonTitles, [])
        XCTAssertTrue(view.testingIsCollectionVisible)
    }

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

    func testBatchActionsRequireContentSelection() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/one.png"), format: .png)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        view.applyItems([item])
        view.applyPresentation(.content)

        view.applySelection([])
        XCTAssertTrue(view.testingBatchActionButtonsDisabled)

        view.applySelection([item.id])
        XCTAssertFalse(view.testingBatchActionButtonsDisabled)

        view.applyItems([])
        view.applySelection([])
        XCTAssertTrue(view.testingBatchActionButtonsDisabled)

        view.applyItems([item])
        view.applySelection([item.id])
        view.applyPresentation(.loading)
        XCTAssertTrue(view.testingBatchActionButtonsDisabled)
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
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.layoutSubtreeIfNeeded()
        view.applyItems([item])
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view.testingCell(at: 0))
        let reloadCount = view.testingReloadCount

        view.applySelection([item.id])

        XCTAssertEqual(loadCount.value, 1)
        XCTAssertEqual(view.testingReloadCount, reloadCount)
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

    func testCommandASelectsAllVisibleItemsAndPublishesSelection() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.jpg"), format: .jpeg)
        let third = ImageItem(url: URL(fileURLWithPath: "/tmp/third.webp"), format: .webp)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var selectedIDs: Set<ImageItem.ID> = []
        view.onSelectionChanged = { selectedIDs = $0 }
        view.apply(items: [first, second, third], selectedIDs: [first.id])

        view.testingPerformKeyDown(
            keyCode: 0,
            modifierFlags: [.command],
            characters: "a"
        )

        XCTAssertEqual(view.testingSelectedIDs, [first.id, second.id, third.id])
        XCTAssertEqual(selectedIDs, [first.id, second.id, third.id])
    }

    func testCommandAStillSelectsAllWhenCapsLockIsEnabled() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.jpg"), format: .jpeg)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        view.apply(items: [first, second], selectedIDs: [first.id])

        view.testingPerformKeyDown(
            keyCode: 0,
            modifierFlags: [.command, .capsLock],
            characters: "A"
        )

        XCTAssertEqual(view.testingSelectedIDs, [first.id, second.id])
    }

    func testDeleteKeyTriggersTrashOnlyWhenSelectionExists() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/delete.png"), format: .png)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var trashRequestCount = 0
        view.onMoveToTrash = { trashRequestCount += 1 }
        view.apply(items: [item], selectedIDs: [item.id])

        view.testingPerformKeyDown(keyCode: 51, characters: "\u{7f}")
        XCTAssertEqual(trashRequestCount, 1)

        view.applySelection([])
        view.testingPerformKeyDown(keyCode: 51, characters: "\u{7f}")
        XCTAssertEqual(trashRequestCount, 1)
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

    func testDoubleClickOnlyOpensHitItemExactlyOnceAndIgnoresBlankSpace() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
        let view = FolderBrowserView(thumbnailProvider: .stub)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.apply(items: [first, second], selectedIDs: [first.id])
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.testingDoubleClickRecognizerCount, 1)
        var opened: [ImageItem] = []
        view.onOpenItem = { opened.append($0) }

        view.testingPerformDoubleClick(onItemAt: 1)
        XCTAssertEqual(opened, [second])

        view.testingPerformDoubleClickOnBlankSpace()
        XCTAssertEqual(opened, [second])
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

    func testApplyingModelFilterUpdatesControlsWithoutSendingUIChangeCallbacks() {
        let view = FolderBrowserView(thumbnailProvider: .stub)
        var searchCallbackCount = 0
        var typeCallbackCount = 0
        view.onSearchChanged = { _ in searchCallbackCount += 1 }
        view.onTypeFilterChanged = { _ in typeCallbackCount += 1 }

        view.applyFilter(FolderFilter(searchText: "cat", allowedFormats: [.png]))

        XCTAssertEqual(view.testingSearchText, "cat")
        XCTAssertEqual(view.testingSelectedTypeFilterTag, SupportedImageFormat.allCases.firstIndex(of: .png))
        XCTAssertEqual(searchCallbackCount, 0)
        XCTAssertEqual(typeCallbackCount, 0)

        view.applyFilter(FolderFilter())

        XCTAssertEqual(view.testingSearchText, "")
        XCTAssertEqual(view.testingSelectedTypeFilterTag, -1)
        XCTAssertEqual(searchCallbackCount, 0)
        XCTAssertEqual(typeCallbackCount, 0)
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
