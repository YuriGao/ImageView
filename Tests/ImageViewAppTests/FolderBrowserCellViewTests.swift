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

    func testPairedRawAndJPEGUseCombinedFilenameWhileLoadingJPEGThumbnail() {
        let rawURL = URL(fileURLWithPath: "/tmp/123.ARW")
        let jpegURL = URL(fileURLWithPath: "/tmp/123.JPG")
        let item = ImageItem(url: jpegURL, format: .jpeg, pairedRawURL: rawURL)
        let requestedURL = FolderBrowserCellLockedURL()
        let provider = ThumbnailProvider(loader: { requestedItem, _, completion in
            requestedURL.set(requestedItem.url)
            completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
            return {}
        })
        let cell = FolderBrowserCellView()
        cell.loadView()

        cell.configure(with: item, thumbnailProvider: provider)

        XCTAssertEqual(cell.testingFilename, "123.ARW / 123.JPG")
        XCTAssertEqual(requestedURL.value, jpegURL)
    }
}

private final class FolderBrowserCellLockedURL: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URL?

    var value: URL? { lock.withLock { storage } }

    func set(_ value: URL) {
        lock.withLock { storage = value }
    }
}
