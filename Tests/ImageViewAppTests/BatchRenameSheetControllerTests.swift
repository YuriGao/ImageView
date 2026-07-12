import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class BatchRenameSheetControllerTests: XCTestCase {
    func testDefaultBaseNameIsLocalized() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/original.png"), format: .png)
        let controller = makeController(items: [item])

        XCTAssertEqual(controller.previewRowsForTesting.first?.newName, "\(AppStrings.text("batchRename.defaultBaseName")) 1.png")
    }

    func testDefaultPaddingUsesItemCountDigits() {
        for (count, expectedPadding) in [(1, 1), (10, 2), (42, 2), (100, 3)] {
            let items = (0..<count).map {
                ImageItem(url: URL(fileURLWithPath: "/tmp/item-\($0).png"), format: .png)
            }
            var receivedPadding: Int?
            _ = BatchRenameSheetController(items: items) { urls, baseName, startNumber, padding in
                receivedPadding = padding
                return BatchFileOperationService().planBatchRename(
                    urls: urls,
                    baseName: baseName,
                    startNumber: startNumber,
                    padding: padding
                )
            }

            XCTAssertEqual(receivedPadding, expectedPadding, "count=\(count)")
        }
    }

    func testPlanConflictsDisplayExactRowsDisableRenameAndRejectConfirm() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let first = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let second = ImageItem(url: folder.appendingPathComponent("two.jpg"), format: .jpeg)
        let duplicateDestination = folder.appendingPathComponent("Shared.png")
        let existingDestination = folder.appendingPathComponent("Existing.jpg")
        let plan = BatchRenamePlan(
            proposals: [
                RenameProposal(source: first.url, destination: duplicateDestination),
                RenameProposal(source: second.url, destination: existingDestination)
            ],
            failures: [
                BatchFileFailure(url: first.url, reason: .duplicateDestination),
                BatchFileFailure(url: second.url, reason: .destinationExists)
            ]
        )
        let controller = BatchRenameSheetController(items: [first, second]) { _, _, _, _ in plan }
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        guard let sheet = controller.window else {
            return XCTFail("Expected rename sheet window")
        }
        parent.beginSheet(sheet)
        var confirmCount = 0
        controller.onConfirm = { _, _ in confirmCount += 1 }

        XCTAssertEqual(controller.previewRowsForTesting, [
            .init(oldName: "one.png", newName: "Shared.png"),
            .init(oldName: "two.jpg", newName: "Existing.jpg")
        ])
        XCTAssertEqual(
            controller.validationErrorForTesting,
            [
                "one.png → Shared.png: \(AppStrings.text("folderBrowser.failure.duplicateDestination"))",
                "two.jpg → Existing.jpg: \(AppStrings.text("folderBrowser.failure.destinationExists"))"
            ].joined(separator: "\n")
        )
        XCTAssertFalse(controller.renameButtonEnabledForTesting)

        controller.confirmForTesting()

        XCTAssertEqual(confirmCount, 0)
        XCTAssertEqual(sheet.sheetParent, parent)
        parent.endSheet(sheet)
    }

    func testPreviewDisplaysOldAndNewNamesPreservingExtensions() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let items = [
            ImageItem(url: folder.appendingPathComponent("IMG_0001.JPG"), format: .jpeg),
            ImageItem(url: folder.appendingPathComponent("diagram.png"), format: .png)
        ]
        let controller = makeController(items: items)

        controller.setBatchRenameInputsForTesting(baseName: "Sprint", startNumber: 8, padding: 3)

        XCTAssertEqual(controller.previewRowsForTesting.map(\.oldName), ["IMG_0001.JPG", "diagram.png"])
        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Sprint 008.JPG", "Sprint 009.png"])
    }

    func testPreviewUsesTrimmedBaseNameToMatchConfirmedParameters() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = makeController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "  Photo  ", startNumber: 1, padding: 0)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { parameters, _ in received = parameters }

        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Photo 1.png"])
        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Photo", startNumber: 1, padding: 0))
    }

    func testConfirmReturnsEnteredRenameParameters() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.webp"), format: .webp)
        let controller = makeController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "Review", startNumber: 3, padding: 2)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { parameters, _ in received = parameters }

        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Review", startNumber: 3, padding: 2))
    }

    func testConfirmEndsSheetBeforeCallingCallback() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/one.png"), format: .png)
        let controller = makeController(items: [item])
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        guard let sheet = controller.window else {
            return XCTFail("Expected rename sheet window")
        }
        parent.beginSheet(sheet)
        var callbackObservedDetachedSheet = false
        controller.onConfirm = { _, _ in
            callbackObservedDetachedSheet = sheet.sheetParent == nil
        }

        controller.confirmForTesting()

        XCTAssertTrue(callbackObservedDetachedSheet)
        XCTAssertNil(sheet.sheetParent)
    }

    func testPaddingZeroConfirmsAndPreviewsUnpaddedNumbers() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = makeController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 1, padding: 0)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { parameters, _ in received = parameters }

        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Batch 1.png"])
        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Batch", startNumber: 1, padding: 0))
        XCTAssertNil(controller.validationErrorForTesting)
    }

    func testConfirmRejectsInvalidInputsWithoutCallingCallback() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.webp"), format: .webp)
        let controller = makeController(items: [item])
        var confirmCount = 0
        controller.onConfirm = { _, _ in confirmCount += 1 }

        controller.setBatchRenameInputsForTesting(baseName: " ", startNumber: 1, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, AppStrings.text("batchRename.validation.baseNameRequired"))

        controller.setBatchRenameInputsForTesting(baseName: "bad/name", startNumber: 1, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, AppStrings.text("batchRename.validation.baseNameInvalid"))

        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 0, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, AppStrings.text("batchRename.validation.numberInvalid"))

        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 1, padding: -1)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, AppStrings.text("batchRename.validation.numberInvalid"))

        XCTAssertEqual(confirmCount, 0)
    }

    private func makeController(items: [ImageItem]) -> BatchRenameSheetController {
        BatchRenameSheetController(items: items) { urls, baseName, startNumber, padding in
            BatchFileOperationService().planBatchRename(
                urls: urls,
                baseName: baseName,
                startNumber: startNumber,
                padding: padding
            )
        }
    }
}
