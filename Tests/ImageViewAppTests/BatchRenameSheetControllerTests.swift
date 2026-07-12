import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class BatchRenameSheetControllerTests: XCTestCase {
    func testDefaultBaseNameIsLocalized() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/original.png"), format: .png)
        let controller = BatchRenameSheetController(items: [item])

        XCTAssertEqual(controller.previewRowsForTesting.first?.newName, "\(AppStrings.text("batchRename.defaultBaseName")) 01.png")
    }

    func testPreviewDisplaysOldAndNewNamesPreservingExtensions() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let items = [
            ImageItem(url: folder.appendingPathComponent("IMG_0001.JPG"), format: .jpeg),
            ImageItem(url: folder.appendingPathComponent("diagram.png"), format: .png)
        ]
        let controller = BatchRenameSheetController(items: items)

        controller.setBatchRenameInputsForTesting(baseName: "Sprint", startNumber: 8, padding: 3)

        XCTAssertEqual(controller.previewRowsForTesting.map(\.oldName), ["IMG_0001.JPG", "diagram.png"])
        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Sprint 008.JPG", "Sprint 009.png"])
    }

    func testPreviewUsesTrimmedBaseNameToMatchConfirmedParameters() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = BatchRenameSheetController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "  Photo  ", startNumber: 1, padding: 0)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { received = $0 }

        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Photo 1.png"])
        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Photo", startNumber: 1, padding: 0))
    }

    func testConfirmReturnsEnteredRenameParameters() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.webp"), format: .webp)
        let controller = BatchRenameSheetController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "Review", startNumber: 3, padding: 2)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { received = $0 }

        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Review", startNumber: 3, padding: 2))
    }

    func testConfirmEndsSheetBeforeCallingCallback() {
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/one.png"), format: .png)
        let controller = BatchRenameSheetController(items: [item])
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
        controller.onConfirm = { _ in
            callbackObservedDetachedSheet = sheet.sheetParent == nil
        }

        controller.confirmForTesting()

        XCTAssertTrue(callbackObservedDetachedSheet)
        XCTAssertNil(sheet.sheetParent)
    }

    func testPaddingZeroConfirmsAndPreviewsUnpaddedNumbers() throws {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = BatchRenameSheetController(items: [item])
        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 1, padding: 0)
        var received: BatchRenameSheetController.RenameParameters?
        controller.onConfirm = { received = $0 }

        XCTAssertEqual(controller.previewRowsForTesting.map(\.newName), ["Batch 1.png"])
        controller.confirmForTesting()

        XCTAssertEqual(try XCTUnwrap(received), .init(baseName: "Batch", startNumber: 1, padding: 0))
        XCTAssertNil(controller.validationErrorForTesting)
    }

    func testConfirmRejectsInvalidInputsWithoutCallingCallback() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.webp"), format: .webp)
        let controller = BatchRenameSheetController(items: [item])
        var confirmCount = 0
        controller.onConfirm = { _ in confirmCount += 1 }

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
}
