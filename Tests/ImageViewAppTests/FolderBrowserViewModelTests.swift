import Combine
import Foundation
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

@MainActor
final class FolderBrowserViewModelTests: XCTestCase {
    func testPresentationDistinguishesEmptyFolderFilteredEmptyAndFailure() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [item] })

        await viewModel.openFolder(folder)
        XCTAssertEqual(viewModel.presentation, .content)

        viewModel.searchText = "missing"
        viewModel.setAllowedFormats([.png])
        XCTAssertEqual(viewModel.presentation, .filteredEmpty)

        viewModel.clearFilters()
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertEqual(viewModel.session?.filter.searchText, "")
        XCTAssertEqual(
            viewModel.session?.filter.allowedFormats,
            Set(SupportedImageFormat.allCases),
            "Clear Filters must restore all supported formats"
        )

        let empty = FolderBrowserViewModel(scanFolder: { _ in [] })
        await empty.openFolder(folder)
        XCTAssertEqual(empty.presentation, .emptyFolder)

        let failed = FolderBrowserViewModel(scanFolder: { _ in throw TestFolderError.denied })
        await failed.openFolder(folder)
        guard case .loadFailed = failed.presentation else {
            return XCTFail("Expected load failure")
        }
        XCTAssertEqual(failed.requestedFolderURL, folder)
        XCTAssertNotNil(failed.loadErrorMessage)
        XCTAssertNil(failed.operationMessage, "folder scan failures must not appear as batch-operation status")
    }

    func testRetryOpenFolderRescansRequestedFolderAndRecoversContent() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let attempts = LockedValue(0)
        let viewModel = FolderBrowserViewModel(scanFolder: { requestedFolder in
            XCTAssertEqual(requestedFolder, folder)
            let attempt = attempts.increment()
            if attempt == 1 { throw TestFolderError.denied }
            return [item]
        })

        await viewModel.openFolder(folder)
        guard case .loadFailed = viewModel.presentation else {
            return XCTFail("Expected initial load failure")
        }

        await viewModel.retryOpenFolder()

        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertNil(viewModel.loadErrorMessage)
        XCTAssertNil(viewModel.operationMessage)
    }

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

    func testCancelOpenFolderRequestIgnoresLateScannerSuccess() async {
        let baselineFolder = URL(fileURLWithPath: "/tmp/baseline", isDirectory: true)
        let cancelledFolder = URL(fileURLWithPath: "/tmp/cancelled", isDirectory: true)
        let baselineItem = ImageItem(url: baselineFolder.appendingPathComponent("baseline.png"), format: .png)
        let lateItem = ImageItem(url: cancelledFolder.appendingPathComponent("late.png"), format: .png)
        let scanner = CancelledOpenFolderScanner(
            baselineFolder: baselineFolder,
            baselineItems: [baselineItem]
        )
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        await viewModel.openFolder(baselineFolder)
        let task = Task { await viewModel.openFolder(cancelledFolder) }
        await scanner.waitUntilPendingScanStarts()

        viewModel.cancelOpenFolderRequest()
        let cancelledSession = viewModel.session
        let cancelledPresentation = viewModel.presentation
        await scanner.finish(with: .success([lateItem]))
        await task.value

        XCTAssertEqual(viewModel.session, cancelledSession)
        XCTAssertEqual(viewModel.presentation, cancelledPresentation)
        XCTAssertEqual(viewModel.session?.folderURL, baselineFolder)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testCancelOpenFolderRequestIgnoresLateScannerFailure() async {
        let baselineFolder = URL(fileURLWithPath: "/tmp/baseline", isDirectory: true)
        let cancelledFolder = URL(fileURLWithPath: "/tmp/cancelled", isDirectory: true)
        let baselineItem = ImageItem(url: baselineFolder.appendingPathComponent("baseline.png"), format: .png)
        let scanner = CancelledOpenFolderScanner(
            baselineFolder: baselineFolder,
            baselineItems: [baselineItem]
        )
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            try await scanner.scan(folder)
        })
        await viewModel.openFolder(baselineFolder)
        let task = Task { await viewModel.openFolder(cancelledFolder) }
        await scanner.waitUntilPendingScanStarts()

        viewModel.cancelOpenFolderRequest()
        let cancelledSession = viewModel.session
        let cancelledPresentation = viewModel.presentation
        await scanner.finish(with: .failure(TestFolderError.denied))
        await task.value

        XCTAssertEqual(viewModel.session, cancelledSession)
        XCTAssertEqual(viewModel.presentation, cancelledPresentation)
        XCTAssertEqual(viewModel.session?.folderURL, baselineFolder)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testCancellationErrorDoesNotPublishLoadFailure() async {
        let baselineFolder = URL(fileURLWithPath: "/tmp/baseline", isDirectory: true)
        let cancelledFolder = URL(fileURLWithPath: "/tmp/cancelled", isDirectory: true)
        let baselineItem = ImageItem(url: baselineFolder.appendingPathComponent("baseline.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            if folder == cancelledFolder { throw CancellationError() }
            return [baselineItem]
        })
        await viewModel.openFolder(baselineFolder)

        await viewModel.openFolder(cancelledFolder)

        XCTAssertEqual(viewModel.session?.folderURL, baselineFolder)
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testInvalidationBeforeCancelledTaskRegistersPreventsScanAndCommit() async {
        let folder = URL(fileURLWithPath: "/tmp/cancel-before-register", isDirectory: true)
        let scans = LockedValue(0)
        let gate = OpenFolderRegistrationGate()
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in
            _ = scans.increment()
            return [ImageItem(url: folder.appendingPathComponent("late.png"), format: .png)]
        })
        let task = Task {
            await gate.wait()
            await viewModel.openFolder(folder)
        }

        task.cancel()
        viewModel.invalidateOpenFolderRequest()
        await gate.release()
        await task.value

        XCTAssertEqual(scans.value, 0)
        XCTAssertNil(viewModel.session)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testInvalidationBetweenCurrentCheckAndCommitRejectsStaleSession() async {
        let baselineFolder = URL(fileURLWithPath: "/tmp/linearized-baseline", isDirectory: true)
        let staleFolder = URL(fileURLWithPath: "/tmp/linearized-stale", isDirectory: true)
        let baselineItem = ImageItem(url: baselineFolder.appendingPathComponent("baseline.png"), format: .png)
        let staleItem = ImageItem(url: staleFolder.appendingPathComponent("stale.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            folder == baselineFolder ? [baselineItem] : [staleItem]
        })
        await viewModel.openFolder(baselineFolder)
        viewModel.beforeOpenFolderCommitForTesting = {
            viewModel.invalidateOpenFolderRequest()
        }

        await viewModel.openFolder(staleFolder)

        XCTAssertEqual(viewModel.session?.folderURL, baselineFolder)
        XCTAssertEqual(viewModel.visibleItems, [baselineItem])
        XCTAssertEqual(viewModel.presentation, .loading)
    }

    func testInvalidationBetweenCurrentCheckAndFailureCommitRejectsLoadError() async {
        let baselineFolder = URL(fileURLWithPath: "/tmp/linearized-error-baseline", isDirectory: true)
        let staleFolder = URL(fileURLWithPath: "/tmp/linearized-error-stale", isDirectory: true)
        let baselineItem = ImageItem(url: baselineFolder.appendingPathComponent("baseline.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            if folder == staleFolder { throw TestFolderError.denied }
            return [baselineItem]
        })
        await viewModel.openFolder(baselineFolder)
        viewModel.beforeOpenFolderCommitForTesting = {
            viewModel.invalidateOpenFolderRequest()
        }

        await viewModel.openFolder(staleFolder)

        XCTAssertEqual(viewModel.session?.folderURL, baselineFolder)
        XCTAssertEqual(viewModel.visibleItems, [baselineItem])
        XCTAssertNil(viewModel.loadErrorMessage)
        XCTAssertEqual(viewModel.presentation, .loading)
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

    func testFilteringOutSelectedItemPermanentlyTrimsSelection() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let apple = ImageItem(url: folder.appendingPathComponent("apple.png"), format: .png)
        let banana = ImageItem(url: folder.appendingPathComponent("banana.jpg"), format: .jpeg)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [apple, banana] })
        await viewModel.openFolder(folder)
        viewModel.setSelection([apple.id, banana.id])

        viewModel.searchText = "app"

        XCTAssertEqual(viewModel.selectedItemIDs, [apple.id])
        XCTAssertEqual(viewModel.selectedItems, [apple])

        viewModel.clearFilters()

        XCTAssertEqual(viewModel.selectedItemIDs, [apple.id])
        XCTAssertEqual(viewModel.selectedItems, [apple])
    }

    func testSetSelectionCanonicalizesIDsToVisibleItemOrder() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let first = ImageItem(url: folder.appendingPathComponent("a.png"), format: .png)
        let second = ImageItem(url: folder.appendingPathComponent("b.jpg"), format: .jpeg)
        let third = ImageItem(url: folder.appendingPathComponent("c.webp"), format: .webp)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [first, second, third] })
        await viewModel.openFolder(folder)

        viewModel.setSelection([third.id, first.id, second.id])

        XCTAssertEqual(viewModel.selectedItems, [first, second, third])
    }

    func testSetSelectionDoesNotRepublishWholeFolderSession() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in [item] })
        await viewModel.openFolder(folder)
        var sessionPublicationCount = 0
        let cancellable = viewModel.$session.dropFirst().sink { _ in
            sessionPublicationCount += 1
        }

        viewModel.setSelection([item.id])

        XCTAssertEqual(viewModel.selectedItems, [item])
        XCTAssertEqual(sessionPublicationCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testSelectingOneItemInLargeFolderMeetsInteractionBudget() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let items = (0..<200_000).map { index in
            ImageItem(url: folder.appendingPathComponent("\(index).png"), format: .png)
        }
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in items })
        await viewModel.openFolder(folder)

        let elapsed = ContinuousClock().measure {
            viewModel.setSelection([items[100_000].id])
        }

        XCTAssertLessThan(elapsed, .milliseconds(20))
        XCTAssertEqual(viewModel.selectedItems, [items[100_000]])
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
        let mutations = LockedValue<[FolderItemURLMutation]>([])
        viewModel.onItemURLMutation = { mutation in
            mutations.withValue { $0.append(mutation) }
        }
        await viewModel.openFolder(folder)
        viewModel.setSelection([old.id])

        let task = viewModel.renameSelected(baseName: "renamed", startNumber: 1, padding: 2)
        await task?.value

        XCTAssertEqual(viewModel.visibleItems.map(\.url), [newURL])
        XCTAssertEqual(viewModel.visibleItems.map(\.url.lastPathComponent), ["renamed 01.png"])
        XCTAssertEqual(viewModel.selectedItems.map(\.url), [newURL])
        XCTAssertEqual(viewModel.operationFailures, [])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededMessage(1))
        XCTAssertEqual(mutations.value, [.renamed([old.url: newURL])])
    }

    func testRenameSelectedMigratesLastOpenedItemToNewURL() async {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let old = ImageItem(url: folder.appendingPathComponent("old.png"), format: .png)
        let newURL = folder.appendingPathComponent("renamed.png")
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: old.url, destination: newURL)],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [old] },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in BatchOperationResult(succeeded: [old.url]) }
        )
        await viewModel.openFolder(folder)
        viewModel.recordOpenedItem(old)
        viewModel.setSelection([old.id])

        let task = viewModel.renameSelected(baseName: "renamed")
        await task?.value

        XCTAssertEqual(viewModel.session?.lastOpenedItemID, newURL)
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

        XCTAssertEqual(received.value?.urls, [failed.url, moved.url])
        XCTAssertEqual(received.value?.destination, destination)
        XCTAssertEqual(received.value?.policy, .skip)
        XCTAssertEqual(viewModel.visibleItems, [failed])
        XCTAssertEqual(viewModel.selectedItems, [failed])
        XCTAssertEqual(viewModel.operationFailures, [expectedFailure])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededAndFailedMessage(succeeded: 1, failed: 1))
    }

    func testExecuteMovePlanRemovesOnlyResultSucceededFromSession() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let destination = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let moved = ImageItem(url: folder.appendingPathComponent("moved.png"), format: .png)
        let conflicted = ImageItem(url: folder.appendingPathComponent("conflicted.jpg"), format: .jpeg)
        let plan = BatchMovePlan(
            proposals: [
                BatchMoveProposal(source: moved.url, destination: destination.appendingPathComponent("moved.png")),
                BatchMoveProposal(
                    source: conflicted.url,
                    destination: destination.appendingPathComponent("conflicted.jpg")
                )
            ],
            failures: [BatchFileFailure(url: conflicted.url, reason: .destinationExists)]
        )
        let executionFailure = BatchFileFailure(url: conflicted.url, reason: .moveFailed("locked"))
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [moved, conflicted] },
            planBatchMove: { _, _, _ in plan },
            executeMovePlan: { _ in
                BatchOperationResult(succeeded: [moved.url], failures: [executionFailure])
            }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([moved.id, conflicted.id])

        let planned = viewModel.planSelectedMove(to: destination, conflictPolicy: .skip)
        let task = planned.flatMap(viewModel.executeMovePlan)
        await task?.value

        XCTAssertEqual(viewModel.visibleItems, [conflicted])
        XCTAssertEqual(viewModel.selectedItems, [conflicted])
        XCTAssertEqual(viewModel.operationFailures, [executionFailure])
        XCTAssertFalse(viewModel.canUndoLastBatchOperation)
    }

    func testSuccessfulPlannedMoveCanBeUndoneOnce() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let destination = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let movedURL = destination.appendingPathComponent("one.png")
        let plan = BatchMovePlan(
            proposals: [BatchMoveProposal(source: item.url, destination: movedURL)],
            failures: []
        )
        let executedPlans = LockedValue<[BatchMovePlan]>([])
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            executeMovePlan: { executedPlan in
                executedPlans.withValue { $0.append(executedPlan) }
                return BatchOperationResult(succeeded: executedPlan.proposals.map(\.source))
            }
        )
        await viewModel.openFolder(folder)

        await viewModel.executeMovePlan(plan)?.value

        XCTAssertTrue(viewModel.canUndoLastBatchOperation)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)

        await viewModel.undoLastBatchOperation()?.value

        XCTAssertFalse(viewModel.canUndoLastBatchOperation)
        XCTAssertEqual(viewModel.visibleItems, [item])
        XCTAssertEqual(viewModel.selectedItems, [item])
        XCTAssertEqual(executedPlans.value, [
            plan,
            BatchMovePlan(
                proposals: [BatchMoveProposal(source: movedURL, destination: item.url)],
                failures: []
            )
        ])
        XCTAssertNil(viewModel.undoLastBatchOperation(), "a finite undo must only be available once")
    }

    func testRenameSelectedFailureTrustsRescanAndKeepsExistingFailedItemSelected() async {
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

        XCTAssertEqual(viewModel.visibleItems.map(\.url), [failed.url, renamed.url])
        XCTAssertEqual(viewModel.selectedItems.map(\.url), [failed.url])
        XCTAssertEqual(viewModel.operationFailures, [failure])
        XCTAssertEqual(viewModel.operationMessage, Self.succeededAndFailedMessage(succeeded: 1, failed: 1))
    }

    func testRenameFailureUsesRealDirectoryScannerToSelectScannableRecoveryURL() async throws {
        let folder = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = ImageItem(url: folder.appendingPathComponent("old.png"), format: .png)
        let actualURL = folder.appendingPathComponent("old batch-rename-recovery-test.png")
        try Data("image".utf8).write(to: original.url)
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: original.url, destination: folder.appendingPathComponent("new.png"))],
            failures: []
        )
        let recovery = BatchRecoveryFailure(
            expectedURL: original.url,
            actualURL: actualURL,
            reason: "injected rollback failure"
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { try await DirectoryScanner().scan(folder: $0) },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in
                BatchOperationResult(
                    failures: [BatchFileFailure(url: original.url, reason: .renameFailed("injected"))],
                    recoveryFailures: [recovery]
                )
            }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([original.id])
        try FileManager.default.moveItem(at: original.url, to: actualURL)

        let task = viewModel.renameSelected(baseName: "new")
        await task?.value

        XCTAssertEqual(viewModel.visibleItems.map(\.url), [actualURL])
        XCTAssertEqual(viewModel.selectedItems.map(\.url), [actualURL])
        XCTAssertEqual(viewModel.operationFailures.map(\.url), [original.url])
        XCTAssertEqual(viewModel.operationRecoveryFailures, [recovery])
    }

    func testRenameFailureRescanErrorClearsStaleItemsAndRetryRestoresRealFolderState() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let stale = ImageItem(url: folder.appendingPathComponent("old.png"), format: .png)
        let recovered = ImageItem(url: folder.appendingPathComponent("old recovery.png"), format: .png)
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: stale.url, destination: folder.appendingPathComponent("new.png"))],
            failures: []
        )
        let scanCount = LockedValue(0)
        let failure = BatchFileFailure(url: stale.url, reason: .renameFailed("injected"))
        let viewModel = FolderBrowserViewModel(
            scanFolder: { requestedFolder in
                XCTAssertEqual(requestedFolder, folder)
                switch scanCount.increment() {
                case 1: return [stale]
                case 2: throw TestFolderError.denied
                default: return [recovered]
                }
            },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in BatchOperationResult(failures: [failure]) }
        )
        await viewModel.openFolder(folder)
        viewModel.setSelection([stale.id])

        let task = viewModel.renameSelected(baseName: "new")
        await task?.value

        XCTAssertEqual(viewModel.session?.folderURL, folder)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertEqual(viewModel.operationFailures, [failure])
        XCTAssertNotNil(viewModel.operationMessage)
        XCTAssertNotNil(viewModel.loadErrorMessage)
        guard case .loadFailed = viewModel.presentation else {
            return XCTFail("Expected an explicit recoverable rescan failure state")
        }

        await viewModel.retryOpenFolder()

        XCTAssertEqual(scanCount.value, 3)
        XCTAssertEqual(viewModel.visibleItems, [recovered])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertEqual(viewModel.presentation, .content)
        XCTAssertNil(viewModel.loadErrorMessage)
    }

    func testRenameFailureIgnoresLateRescanSuccessAfterOpeningDifferentFolder() async {
        let folderA = URL(fileURLWithPath: "/tmp/photos-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/photos-b", isDirectory: true)
        let itemA = ImageItem(url: folderA.appendingPathComponent("a.png"), format: .png)
        let recoveredA = ImageItem(url: folderA.appendingPathComponent("a recovered.png"), format: .png)
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        let scanner = RenameRescanSessionScanner(
            folderA: folderA,
            initialItemsA: [itemA],
            folderB: folderB,
            itemsB: [itemB]
        )
        let failure = BatchFileFailure(url: itemA.url, reason: .renameFailed("injected"))
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: itemA.url, destination: folderA.appendingPathComponent("new.png"))],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { try await scanner.scan($0) },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in BatchOperationResult(failures: [failure]) }
        )
        await viewModel.openFolder(folderA)
        viewModel.setSelection([itemA.id])

        let renameTask = viewModel.renameSelected(baseName: "new")
        await scanner.waitUntilRescanStarts()
        await viewModel.openFolder(folderB)
        await scanner.finishRescan(with: .success([recoveredA]))
        await renameTask?.value

        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertTrue(viewModel.operationFailures.isEmpty)
        XCTAssertNil(viewModel.operationMessage)
        XCTAssertNil(viewModel.loadErrorMessage)
        XCTAssertFalse(viewModel.isOperating)
    }

    func testRenameFailureIgnoresLateRescanFailureAfterOpeningDifferentFolder() async {
        let folderA = URL(fileURLWithPath: "/tmp/photos-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/photos-b", isDirectory: true)
        let itemA = ImageItem(url: folderA.appendingPathComponent("a.png"), format: .png)
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        let scanner = RenameRescanSessionScanner(
            folderA: folderA,
            initialItemsA: [itemA],
            folderB: folderB,
            itemsB: [itemB]
        )
        let failure = BatchFileFailure(url: itemA.url, reason: .renameFailed("injected"))
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: itemA.url, destination: folderA.appendingPathComponent("new.png"))],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { try await scanner.scan($0) },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in BatchOperationResult(failures: [failure]) }
        )
        await viewModel.openFolder(folderA)
        viewModel.setSelection([itemA.id])

        let renameTask = viewModel.renameSelected(baseName: "new")
        await scanner.waitUntilRescanStarts()
        await viewModel.openFolder(folderB)
        await scanner.finishRescan(with: .failure(TestFolderError.denied))
        await renameTask?.value

        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertTrue(viewModel.operationFailures.isEmpty)
        XCTAssertNil(viewModel.operationMessage)
        XCTAssertNil(viewModel.loadErrorMessage)
        XCTAssertFalse(viewModel.isOperating)
    }

    func testSuccessfulRenamePublishesFileMutationWithoutChangingReplacementFolder() async {
        let folderA = URL(fileURLWithPath: "/tmp/photos-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/photos-b", isDirectory: true)
        let itemA = ImageItem(url: folderA.appendingPathComponent("a.png"), format: .png)
        let renamedA = folderA.appendingPathComponent("new.png")
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        let gate = BlockingBatchOperation(result: BatchOperationResult(succeeded: [itemA.url]))
        let mutations = LockedValue<[FolderItemURLMutation]>([])
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: itemA.url, destination: renamedA)],
            failures: []
        )
        let viewModel = FolderBrowserViewModel(
            scanFolder: { folder in folder == folderA ? [itemA] : [itemB] },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in gate.run() }
        )
        viewModel.onItemURLMutation = { mutation in
            mutations.withValue { $0.append(mutation) }
        }
        await viewModel.openFolder(folderA)
        viewModel.setSelection([itemA.id])

        let renameTask = viewModel.renameSelected(baseName: "new")
        await gate.waitUntilStarted()
        await viewModel.openFolder(folderB)
        gate.finish()
        await renameTask?.value

        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertTrue(viewModel.operationFailures.isEmpty)
        XCTAssertNil(viewModel.operationMessage)
        XCTAssertEqual(mutations.value, [
            .renamed([itemA.url: renamedA])
        ])
        XCTAssertFalse(viewModel.isOperating)
    }

    func testStaleRenameRecoveryPublishesGlobalNoticeWithoutPollutingReplacementSession() async {
        let folderA = URL(fileURLWithPath: "/tmp/photos-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/photos-b", isDirectory: true)
        let itemA = ImageItem(url: folderA.appendingPathComponent("a.png"), format: .png)
        let itemB = ImageItem(url: folderB.appendingPathComponent("b.png"), format: .png)
        let recovery = BatchRecoveryFailure(
            expectedURL: itemA.url,
            actualURL: folderA.appendingPathComponent(".batch-rename-stranded.tmp"),
            reason: "rollback permission denied"
        )
        let failure = BatchFileFailure(url: itemA.url, reason: .renameFailed("injected"))
        let scanner = RenameRescanSessionScanner(
            folderA: folderA,
            initialItemsA: [itemA],
            folderB: folderB,
            itemsB: [itemB]
        )
        let plan = BatchRenamePlan(
            proposals: [RenameProposal(source: itemA.url, destination: folderA.appendingPathComponent("new.png"))],
            failures: []
        )
        let notice = LockedValue<RecoveryNotice?>(nil)
        let viewModel = FolderBrowserViewModel(
            scanFolder: { try await scanner.scan($0) },
            planBatchRename: { _, _, _, _ in plan },
            executeRenamePlan: { _ in
                BatchOperationResult(failures: [failure], recoveryFailures: [recovery])
            }
        )
        viewModel.onRecoveryRequired = { folderURL, failures in
            notice.set(RecoveryNotice(folderURL: folderURL, failures: failures))
        }
        await viewModel.openFolder(folderA)
        viewModel.setSelection([itemA.id])

        let renameTask = viewModel.renameSelected(baseName: "new")
        await scanner.waitUntilRescanStarts()
        await viewModel.openFolder(folderB)
        await scanner.finishRescan(with: .success([itemA]))
        await renameTask?.value

        XCTAssertEqual(notice.value, RecoveryNotice(folderURL: folderA, failures: [recovery]))
        XCTAssertEqual(viewModel.session?.folderURL, folderB)
        XCTAssertEqual(viewModel.visibleItems, [itemB])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
        XCTAssertTrue(viewModel.operationFailures.isEmpty)
        XCTAssertTrue(viewModel.operationRecoveryFailures.isEmpty)
        XCTAssertNil(viewModel.operationMessage)
        XCTAssertNil(viewModel.loadErrorMessage)
        XCTAssertFalse(viewModel.isOperating)
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

    func withValue(_ update: (inout Value) -> Void) {
        lock.lock()
        update(&storedValue)
        lock.unlock()
    }
}

private extension LockedValue where Value == Int {
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storedValue += 1
        return storedValue
    }
}

private enum TestFolderError: LocalizedError {
    case denied

    var errorDescription: String? { "Permission denied" }
}

private struct RecoveryNotice: Equatable {
    let folderURL: URL
    let failures: [BatchRecoveryFailure]
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

private actor CancelledOpenFolderScanner {
    private let baselineFolder: URL
    private let baselineItems: [ImageItem]
    private var pendingContinuation: CheckedContinuation<[ImageItem], Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingScanStarted = false

    init(baselineFolder: URL, baselineItems: [ImageItem]) {
        self.baselineFolder = baselineFolder
        self.baselineItems = baselineItems
    }

    func scan(_ folder: URL) async throws -> [ImageItem] {
        guard folder != baselineFolder else { return baselineItems }
        pendingScanStarted = true
        let pending = startWaiters
        startWaiters.removeAll()
        pending.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { pendingContinuation = $0 }
    }

    func waitUntilPendingScanStarts() async {
        guard !pendingScanStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(with result: Result<[ImageItem], Error>) {
        pendingContinuation?.resume(with: result)
        pendingContinuation = nil
    }
}

private actor RenameRescanSessionScanner {
    private let folderA: URL
    private let initialItemsA: [ImageItem]
    private let folderB: URL
    private let itemsB: [ImageItem]
    private var scanCountA = 0
    private var rescanContinuation: CheckedContinuation<[ImageItem], Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(folderA: URL, initialItemsA: [ImageItem], folderB: URL, itemsB: [ImageItem]) {
        self.folderA = folderA
        self.initialItemsA = initialItemsA
        self.folderB = folderB
        self.itemsB = itemsB
    }

    func scan(_ folder: URL) async throws -> [ImageItem] {
        if folder == folderB { return itemsB }
        precondition(folder == folderA)
        scanCountA += 1
        if scanCountA == 1 { return initialItemsA }
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { rescanContinuation = $0 }
    }

    func waitUntilRescanStarts() async {
        guard rescanContinuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finishRescan(with result: Result<[ImageItem], Error>) {
        rescanContinuation?.resume(with: result)
        rescanContinuation = nil
    }
}

private actor OpenFolderRegistrationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
