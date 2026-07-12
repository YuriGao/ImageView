import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class FolderBrowserCellViewTests: XCTestCase {
    func testSelectedAppearanceRefreshesWhenEffectiveAppearanceChanges() {
        let cell = FolderBrowserCellView()
        cell.loadView()
        cell.isSelected = true
        let initialRefreshCount = cell.testingAppearanceRefreshCount
        cell.view.appearance = NSAppearance(named: .aqua)
        cell.view.viewDidChangeEffectiveAppearance()
        let lightBackground = cell.testingSelectionBackgroundColor

        cell.view.appearance = NSAppearance(named: .darkAqua)
        cell.view.viewDidChangeEffectiveAppearance()

        XCTAssertNotEqual(cell.testingSelectionBackgroundColor, lightBackground)
        XCTAssertGreaterThanOrEqual(cell.testingAppearanceRefreshCount - initialRefreshCount, 2)
    }

    func testSelectionChangesAppearanceWithoutChangingLayoutInLightAndDarkAppearances() {
        let item = ImageItem(
            url: URL(fileURLWithPath: "/tmp/a-very-long-image-filename-that-must-remain-visible.png"),
            format: .png
        )
        let provider = ThumbnailProvider(loader: { _, _, completion in
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let cell = FolderBrowserCellView()
            cell.loadView()
            cell.view.appearance = NSAppearance(named: appearanceName)
            cell.view.widthAnchor.constraint(equalToConstant: 148).isActive = true
            cell.configure(with: item, thumbnailProvider: provider)
            let size = cell.view.fittingSize

            cell.isSelected = true
            XCTAssertFalse(cell.testingFilename.isEmpty)
            XCTAssertTrue(cell.testingShowsSelection)
            XCTAssertGreaterThan(cell.view.layer?.backgroundColor?.alpha ?? 0, 0)
            XCTAssertGreaterThan(cell.view.layer?.borderWidth ?? 0, 0)
            XCTAssertEqual(cell.view.fittingSize, size)

            cell.isSelected = false
            XCTAssertFalse(cell.testingShowsSelection)
            XCTAssertEqual(cell.view.fittingSize, size)
        }
    }
}
