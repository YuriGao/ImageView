import Foundation
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

@MainActor
final class FolderBrowserViewModelTests: XCTestCase {
    func testOpenFolderKeepsLatestRequestWhenEarlierScanFinishesLater() async {
        let slowFolder = URL(fileURLWithPath: "/tmp/slow", isDirectory: true)
        let fastFolder = URL(fileURLWithPath: "/tmp/fast", isDirectory: true)
        let slowItem = ImageItem(url: slowFolder.appendingPathComponent("slow.png"), format: .png)
        let fastItem = ImageItem(url: fastFolder.appendingPathComponent("fast.jpg"), format: .jpeg)
        let scanner = ControlledFolderScanner(
            slowFolder: slowFolder,
            slowItems: [slowItem],
            fastItems: [fastItem]
        )
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })

        let slowTask = Task {
            await viewModel.openFolder(slowFolder)
        }
        await scanner.waitForSlowScanToStart()

        await viewModel.openFolder(fastFolder)
        XCTAssertEqual(viewModel.session?.folderURL, fastFolder)
        XCTAssertEqual(viewModel.visibleItems, [fastItem])
        XCTAssertFalse(viewModel.isLoading)

        await scanner.finishSlowScan()
        await slowTask.value

        XCTAssertEqual(viewModel.session?.folderURL, fastFolder)
        XCTAssertEqual(viewModel.visibleItems, [fastItem])
        XCTAssertFalse(viewModel.isLoading)
    }

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
        XCTAssertEqual(viewModel.operationMessage, Self.succeededAndFailedMessage(succeeded: 1, failed: 1))
    }

    func testRenameSelectedUpdatesVisibleItemsAndSelectionToNewURL() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let old = ImageItem(url: folder.appendingPathComponent("old.png"), format: .png)
        let newURL = folder.appendingPathComponent("renamed 01.png")
        let proposal = RenameProposal(source: old.url, destination: newURL)
        let plan = BatchRenamePlan(proposals: [proposal], failures: [])
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [old] },
            planBatchRename: { urls, baseName, startNumber, padding in
                XCTAssertEqual(urls, [old.url])
                XCTAssertEqual(baseName, "renamed")
                XCTAssertEqual(startNumber, 1)
                XCTAssertEqual(padding, 2)
                return plan
            },
            executeRenamePlan: { receivedPlan in
                XCTAssertEqual(receivedPlan, plan)
                return BatchOperationResult(succeeded: [old.url])
            }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([old.id])

        let task = viewModel.renameSelected(baseName: "renamed", startNumber: 1, padding: 2)
        await task?.value

        XCTAssertEqual(viewModel.visibleItems.map(\.url), [newURL])
        XCTAssertEqual(viewModel.visibleItems.map(\.url.lastPathComponent), ["renamed 01.png"])
        XCTAssertEqual(viewModel.selectedItems.map(\.url), [newURL])
        XCTAssertEqual(viewModel.operationFailures, [])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededMessage(1))
    }

    func testMoveSelectedToFolderUsesInjectedOperationAndRemovesSucceededButKeepsFailuresSelected() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let destination = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let moved = ImageItem(url: folder.appendingPathComponent("moved.png"), format: .png)
        let failed = ImageItem(url: folder.appendingPathComponent("failed.jpg"), format: .jpeg)
        let received = LockedValue<(urls: [URL], destination: URL, policy: MoveConflictPolicy)?>(nil)
        let expectedFailure = BatchFileFailure(url: failed.url, reason: .destinationExists)
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [moved, failed] },
            moveToFolder: { urls, destinationFolder, policy in
                received.set((urls, destinationFolder, policy))
                return BatchOperationResult(succeeded: [moved.url], failures: [expectedFailure])
            }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([moved.id, failed.id])

        let task = viewModel.moveSelected(to: destination, conflictPolicy: .skip)
        await task?.value

        XCTAssertEqual(received.value?.urls, [moved.url, failed.url])
        XCTAssertEqual(received.value?.destination, destination)
        XCTAssertEqual(received.value?.policy, .skip)
        XCTAssertEqual(viewModel.visibleItems, [failed])
        XCTAssertEqual(viewModel.selectedItems, [failed])
        XCTAssertEqual(viewModel.operationFailures, [expectedFailure])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededAndFailedMessage(succeeded: 1, failed: 1))
    }

    func testRenameSelectedKeepsFailedItemsSelectedAndDoesNotRemoveThemFromSession() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let renamed = ImageItem(url: folder.appendingPathComponent("old.png"), format: .png)
        let failed = ImageItem(url: folder.appendingPathComponent("blocked.jpg"), format: .jpeg)
        let renamedURL = folder.appendingPathComponent("Batch 01.png")
        let plan = BatchRenamePlan(
            proposals: [
                RenameProposal(source: renamed.url, destination: renamedURL),
                RenameProposal(source: failed.url, destination: folder.appendingPathComponent("Batch 02.jpg"))
            ],
            failures: []
        )
        let failure = BatchFileFailure(url: failed.url, reason: .renameFailed("locked"))
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [renamed, failed] },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in BatchOperationResult(succeeded: [renamed.url], failures: [failure]) }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([renamed.id, failed.id])

        let task = viewModel.renameSelected(baseName: "Batch", startNumber: 1, padding: 2)
        await task?.value

        XCTAssertEqual(viewModel.visibleItems.map(\.url), [renamedURL, failed.url])
        XCTAssertEqual(viewModel.selectedItems.map(\.url), [failed.url, renamedURL])
        XCTAssertEqual(viewModel.operationFailures, [failure])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededAndFailedMessage(succeeded: 1, failed: 1))
    }

    func testMoveSelectedToTrashSetsOperatingWhileBackgroundOperationRunsAndClearsAfterResult() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let gate = BlockingBatchOperation(result: BatchOperationResult(succeeded: [item.url]))
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToTrash: { urls in
                XCTAssertEqual(urls, [item.url])
                return gate.run()
            }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([item.id])

        let task = viewModel.moveSelectedToTrash()

        await gate.waitUntilStarted()
        XCTAssertTrue(viewModel.isOperating)
        XCTAssertNil(viewModel.moveSelectedToTrash(), "duplicate clicks should be ignored while an operation is running")

        gate.finish()
        await task?.value

        XCTAssertFalse(viewModel.isOperating)
        XCTAssertEqual(viewModel.visibleItems, [])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededMessage(1))
    }

    private static func succeededMessage(_ count: Int) -> String {
        String(format: AppStrings.text("folderBrowser.operation.succeeded"), count)
    }

    private static func succeededAndFailedMessage(succeeded: Int, failed: Int) -> String {
        String(
            format: AppStrings.text("folderBrowser.operation.succeededAndFailed"),
            succeeded,
            failed
        )
    }
}

private final class BlockingBatchOperation: @unchecked Sendable {
    private let result: BatchOperationResult
    private let started = AsyncStartFlag()
    private let finished = DispatchSemaphore(value: 0)

    init(result: BatchOperationResult) {
        self.result = result
    }

    func run() -> BatchOperationResult {
        Task { await started.markStarted() }
        finished.wait()
        return result
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func finish() {
        finished.signal()
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private actor AsyncStartFlag {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func markStarted() {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor ControlledFolderScanner {
    private let slowFolder: URL
    private let slowItems: [ImageItem]
    private let fastItems: [ImageItem]
    private var slowContinuation: CheckedContinuation<[ImageItem], Error>?
    private var slowScanStartedContinuation: CheckedContinuation<Void, Never>?

    init(slowFolder: URL, slowItems: [ImageItem], fastItems: [ImageItem]) {
        self.slowFolder = slowFolder
        self.slowItems = slowItems
        self.fastItems = fastItems
    }

    func scan(_ folder: URL) async throws -> [ImageItem] {
        guard folder == slowFolder else {
            return fastItems
        }

        return try await withCheckedThrowingContinuation { continuation in
            slowContinuation = continuation
            slowScanStartedContinuation?.resume()
            slowScanStartedContinuation = nil
        }
    }

    func waitForSlowScanToStart() async {
        guard slowContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            slowScanStartedContinuation = continuation
        }
    }

    func finishSlowScan() {
        slowContinuation?.resume(returning: slowItems)
        slowContinuation = nil
    }
}
