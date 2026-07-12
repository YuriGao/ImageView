import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class BatchRenameSheetControllerTests: XCTestCase {
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

    func testConfirmRejectsInvalidInputsWithoutCallingCallback() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.webp"), format: .webp)
        let controller = BatchRenameSheetController(items: [item])
        var confirmCount = 0
        controller.onConfirm = { _ in confirmCount += 1 }

        controller.setBatchRenameInputsForTesting(baseName: " ", startNumber: 1, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, "Base name is required.")

        controller.setBatchRenameInputsForTesting(baseName: "bad/name", startNumber: 1, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, "Base name cannot contain / or :.")

        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 0, padding: 2)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, "Start number and padding must be positive.")

        controller.setBatchRenameInputsForTesting(baseName: "Batch", startNumber: 1, padding: 0)
        controller.confirmForTesting()
        XCTAssertEqual(controller.validationErrorForTesting, "Start number and padding must be positive.")

        XCTAssertEqual(confirmCount, 0)
    }
}
