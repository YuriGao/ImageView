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
}
