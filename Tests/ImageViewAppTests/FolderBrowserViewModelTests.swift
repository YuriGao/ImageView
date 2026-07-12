import Foundation
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

@MainActor
final class FolderBrowserViewModelTests: XCTestCase {
    func testOpenFolderLoadsSessionWithNoSelection() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let items = [
            ImageItem(url: folder.appendingPathComponent("one.png"), format: .png),
            ImageItem(url: folder.appendingPathComponent("two.jpg"), format: .jpeg)
        ]
        let viewModel = FolderBrowserViewModel(scanFolder: { requestedFolder in
            XCTAssertEqual(requestedFolder, folder)
            return items
        })

        await viewModel.openFolder(folder)

        XCTAssertEqual(viewModel.session?.folderURL, folder)
        XCTAssertEqual(viewModel.visibleItems, items)
        XCTAssertEqual(viewModel.selectedItems, [])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.operationMessage)
    }

    func testSearchTextUpdatesVisibleItems() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let apple = ImageItem(url: folder.appendingPathComponent("apple.png"), format: .png)
        let banana = ImageItem(url: folder.appendingPathComponent("banana.jpg"), format: .jpeg)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [apple, banana] })
        await viewModel.openFolder(folder)

        viewModel.searchText = "app"

        XCTAssertEqual(viewModel.visibleItems, [apple])
    }

    func testApplyingTrashLikeResultRemovesSucceededAndKeepsFailedSelected() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let removed = ImageItem(url: folder.appendingPathComponent("removed.png"), format: .png)
        let failed = ImageItem(url: folder.appendingPathComponent("failed.jpg"), format: .jpeg)
        let untouched = ImageItem(url: folder.appendingPathComponent("untouched.webp"), format: .webp)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [removed, failed, untouched] })
        await viewModel.openFolder(folder)
        viewModel.setSelection([removed.id, failed.id])

        let result = BatchOperationResult(
            succeeded: [removed.url],
            failures: [BatchFileFailure(url: failed.url, reason: .trashFailed("permission denied"))]
        )
        viewModel.applyOperationResult(result, removingSucceeded: true)

        XCTAssertEqual(viewModel.visibleItems, [failed, untouched])
        XCTAssertEqual(viewModel.selectedItems, [failed])
        XCTAssertEqual(viewModel.operationFailures, result.failures)
        XCTAssertEqual(viewModel.operationMessage, "1 succeeded, 1 failed")
    }
}
