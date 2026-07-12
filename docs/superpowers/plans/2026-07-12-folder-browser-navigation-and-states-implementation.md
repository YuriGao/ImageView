# Folder Browser Navigation and States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove folder-grid click flicker, make selection visible, add reversible grid/viewer navigation with Back and Forward, add title-bar hover feedback, and provide recoverable folder loading and empty states.

**Architecture:** Keep `FolderSession` and both existing view models alive while a small `MainWindowController` route state switches the folder grid and viewer. Split item updates from selection synchronization so selection never reloads thumbnails. Derive a typed folder presentation state in `FolderBrowserViewModel`, render it in `FolderBrowserView`, and keep folder-load errors separate from batch-operation status.

**Tech Stack:** Swift 6, AppKit, Combine, XCTest, Swift Package Manager.

---

## File Structure

- Create `Sources/ImageViewApp/Controls/HoverToolbarButton.swift`: shared title-bar normal, hover, pressed, focus, and disabled rendering.
- Modify `Sources/ImageViewApp/FolderBrowser/FolderBrowserCellView.swift`: render selected cells.
- Modify `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`: separate item and selection updates; render typed presentation states and recovery actions.
- Modify `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`: publish explicit loading/content/empty/filter-empty/failure state and retry/clear-filter operations.
- Modify `Sources/ImageViewApp/MainWindowController.swift`: coordinate live grid/viewer routes, grid toggle, Back/Forward buttons, and view-model bindings.
- Modify `Sources/ImageViewApp/Localization/AppStrings.swift` and both `Localizable.strings`: localize new states, recovery actions, tooltips, and accessibility labels.
- Modify `Tests/ImageViewAppTests/FolderBrowserCellViewTests.swift`, `FolderBrowserViewTests.swift`, `FolderBrowserViewModelTests.swift`, `MainWindowControllerTests.swift`, and `AppStringsTests.swift`: cover each behavior before implementation.

### Task 1: Stop Selection Reloads and Render Selection

**Files:**
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserCellView.swift`
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Create: `Tests/ImageViewAppTests/FolderBrowserCellViewTests.swift`
- Modify: `Tests/ImageViewAppTests/FolderBrowserViewTests.swift`

- [ ] **Step 1: Write failing selection tests**

Add a thumbnail loader count to `FolderBrowserViewTests` and assert that selection-only synchronization does not reload cells:

```swift
func testSelectionOnlyUpdateDoesNotRestartThumbnailRequests() {
    let item = ImageItem(url: URL(fileURLWithPath: "/tmp/one.png"), format: .png)
    var loadCount = 0
    let provider = ThumbnailProvider(loader: { _, _, completion in
        loadCount += 1
        completion(.success(NSImage(size: NSSize(width: 8, height: 8))))
        return {}
    })
    let view = FolderBrowserView(thumbnailProvider: provider)
    view.applyItems([item])
    _ = view.testingCell(at: 0)

    view.applySelection([item.id])

    XCTAssertEqual(loadCount, 1)
    XCTAssertEqual(view.testingSelectedIDs, [item.id])
}
```

Create `FolderBrowserCellViewTests.swift`:

```swift
@MainActor
final class FolderBrowserCellViewTests: XCTestCase {
    func testSelectionChangesAppearanceWithoutChangingLayout() {
        let cell = FolderBrowserCellView()
        cell.loadView()
        let size = cell.view.fittingSize

        cell.isSelected = true
        XCTAssertTrue(cell.testingShowsSelection)
        XCTAssertEqual(cell.view.fittingSize, size)

        cell.isSelected = false
        XCTAssertFalse(cell.testingShowsSelection)
    }
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter FolderBrowserViewTests/testSelectionOnlyUpdateDoesNotRestartThumbnailRequests
swift test --disable-sandbox --filter FolderBrowserCellViewTests
```

Expected: compile failures because `applyItems`, `applySelection`, `testingCell`, and `testingShowsSelection` do not exist.

- [ ] **Step 3: Implement independent item and selection paths**

Replace the combined `apply(items:selectedIDs:)` implementation with:

```swift
func applyItems(_ newItems: [ImageItem]) {
    guard items != newItems else { return }
    items = newItems
    collectionView.reloadData()
}

func applySelection(_ selectedIDs: Set<ImageItem.ID>) {
    let indexPaths = Set(items.enumerated().compactMap { index, item in
        selectedIDs.contains(item.id) ? IndexPath(item: index, section: 0) : nil
    })
    guard collectionView.selectionIndexPaths != indexPaths else { return }
    collectionView.selectionIndexPaths = indexPaths
}
```

Keep `apply(items:selectedIDs:)` as a compatibility wrapper that calls `applyItems` and then `applySelection`. In `MainWindowController`, deduplicate item projections before calling `applyItems`, then always call `applySelection`.

In `FolderBrowserCellView`, add an appearance update driven by `isSelected`:

```swift
override var isSelected: Bool {
    didSet { updateSelectionAppearance() }
}

private func updateSelectionAppearance() {
    view.wantsLayer = true
    view.layer?.cornerRadius = 10
    view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
    view.layer?.borderWidth = isSelected ? 1 : 0
    view.layer?.borderColor = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.65).cgColor
    filenameField.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter FolderBrowserCellViewTests
swift test --disable-sandbox --filter FolderBrowserViewTests
```

Expected: all focused tests pass and the loader count remains `1` after a selection-only update.

- [ ] **Step 5: Commit the selection fix**

```bash
git add Sources/ImageViewApp/FolderBrowser Tests/ImageViewAppTests/FolderBrowserCellViewTests.swift Tests/ImageViewAppTests/FolderBrowserViewTests.swift Sources/ImageViewApp/MainWindowController.swift
git commit -m "fix: keep folder selection from reloading thumbnails"
```

### Task 2: Add Typed Folder Presentation and Recovery

**Files:**
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`
- Modify: `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`
- Modify: `Tests/ImageViewAppTests/FolderBrowserViewTests.swift`

- [ ] **Step 1: Write failing presentation-state tests**

Add tests that cover all state transitions:

```swift
func testPresentationDistinguishesEmptyFolderFilteredEmptyAndFailure() async {
    let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
    let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
    let viewModel = FolderBrowserViewModel(scanFolder: { _ in [item] })
    await viewModel.openFolder(folder)
    XCTAssertEqual(viewModel.presentation, .content)

    viewModel.searchText = "missing"
    XCTAssertEqual(viewModel.presentation, .filteredEmpty)

    viewModel.clearFilters()
    XCTAssertEqual(viewModel.presentation, .content)

    let empty = FolderBrowserViewModel(scanFolder: { _ in [] })
    await empty.openFolder(folder)
    XCTAssertEqual(empty.presentation, .emptyFolder)

    let failed = FolderBrowserViewModel(scanFolder: { _ in throw TestFolderError.denied })
    await failed.openFolder(folder)
    guard case .loadFailed = failed.presentation else { return XCTFail("Expected load failure") }
}
```

Add `FolderBrowserViewTests` assertions for title, message, visible recovery buttons, and callbacks for `.loading`, `.emptyFolder`, `.filteredEmpty`, and `.loadFailed`.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --disable-sandbox --filter FolderBrowserViewModelTests/testPresentationDistinguishesEmptyFolderFilteredEmptyAndFailure
swift test --disable-sandbox --filter FolderBrowserViewTests
```

Expected: compile failure because `FolderBrowserPresentation`, `presentation`, `clearFilters`, and view recovery APIs do not exist.

- [ ] **Step 3: Implement presentation state in the view model**

Add:

```swift
enum FolderBrowserPresentation: Equatable {
    case loading
    case content
    case emptyFolder
    case filteredEmpty
    case loadFailed(String)
}

@Published private(set) var loadErrorMessage: String?
private(set) var requestedFolderURL: URL?

var presentation: FolderBrowserPresentation {
    if isLoading { return .loading }
    if let loadErrorMessage { return .loadFailed(loadErrorMessage) }
    guard let session else { return .loading }
    if session.items.isEmpty { return .emptyFolder }
    if session.visibleItems.isEmpty { return .filteredEmpty }
    return .content
}
```

Set `requestedFolderURL` before scanning, set `loadErrorMessage` only on scan failure, do not put scan failures into `operationMessage`, and add:

```swift
func retryOpenFolder() async {
    guard let requestedFolderURL else { return }
    await openFolder(requestedFolderURL)
}

func clearFilters() {
    searchText = ""
    setAllowedFormats(Set(SupportedImageFormat.allCases))
}
```

- [ ] **Step 4: Render and wire recovery states**

Add `onClearFilters`, `onRetryFolder`, and `onChooseAnotherFolder` callbacks. Build one centered state stack with progress indicator, title, message, primary button, and secondary button. `applyPresentation(_:)` must hide or show the collection and recovery controls without rebuilding the toolbar.

- [ ] **Step 5: Run focused tests and verify GREEN**

```bash
swift test --disable-sandbox --filter FolderBrowserViewModelTests
swift test --disable-sandbox --filter FolderBrowserViewTests
```

Expected: all folder browser view-model and view tests pass.

- [ ] **Step 6: Commit presentation states**

```bash
git add Sources/ImageViewApp/FolderBrowser Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift Tests/ImageViewAppTests/FolderBrowserViewTests.swift
git commit -m "feat: add recoverable folder browser states"
```

### Task 3: Add Live Grid/Viewer Routes and Grid Toggle

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewCore/Folder/FolderSession.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`
- Modify: `Tests/ImageViewCoreTests/FolderSessionTests.swift`

- [ ] **Step 1: Write failing route tests**

Add controller tests:

```swift
func testGridButtonTogglesBackToLiveViewerWithoutRescanning() async throws {
    let fixture = try makeFolderNavigationFixture()
    await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.item])
    fixture.controller.openFirstFolderBrowserItemForTesting()

    fixture.controller.performTitleBarGridToggleForTesting()
    XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)

    fixture.controller.performTitleBarGridToggleForTesting()
    XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
    XCTAssertEqual(fixture.scanCount.value, 1)
}

func testOpeningGridItemEnablesBackAndBackForwardReuseLiveViews() async throws {
    let fixture = try makeFolderNavigationFixture()
    await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.item])
    fixture.controller.openFirstFolderBrowserItemForTesting()

    XCTAssertTrue(fixture.controller.canGoBackForTesting)
    fixture.controller.goBackForTesting()
    XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
    XCTAssertTrue(fixture.controller.canGoForwardForTesting)
    fixture.controller.goForwardForTesting()
    XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
}
```

Use this fixture helper in the same test class so the scan count and image file are real:

```swift
private func makeFolderNavigationFixture() throws -> (
    folder: URL,
    item: ImageItem,
    scanCount: MainWindowLockedValue<Int>,
    controller: MainWindowController
) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let imageURL = folder.appendingPathComponent("one.png")
    try writeTestPNG(to: imageURL)
    let item = ImageItem(url: imageURL, format: .png)
    let scanCount = MainWindowLockedValue(0)
    let viewModel = FolderBrowserViewModel(scanFolder: { _ in
        scanCount.update { $0 += 1 }
        return [item]
    })
    let controller = MainWindowController(
        settings: AppSettings(defaults: makeIsolatedDefaults()),
        folderBrowserViewModel: viewModel
    )
    return (folder, item, scanCount, controller)
}
```

- [ ] **Step 2: Run route tests and verify RED**

```bash
swift test --disable-sandbox --filter MainWindowControllerTests/testGridButtonTogglesBackToLiveViewerWithoutRescanning
swift test --disable-sandbox --filter MainWindowControllerTests/testOpeningGridItemEnablesBackAndBackForwardReuseLiveViews
```

Expected: compile failure for the new navigation test API.

- [ ] **Step 3: Implement minimal route coordinator**

Add private state to `MainWindowController`:

```swift
private enum ContentRoute: Equatable {
    case viewer(URL)
    case folder(URL)
}

private var currentRoute: ContentRoute?
private var backRoute: ContentRoute?
private var forwardRoute: ContentRoute?
```

Create `showRoute(_:recordHistory:)` that only calls `enterFolderBrowserMode()` or `exitFolderBrowserMode()` for an existing route. Grid item opening records the folder route before calling the existing image open pipeline. Back and Forward swap the current and counterpart routes without rescanning or decoding.

When creating a folder route from a directly opened image, scan once. When already in the folder route, the grid action selects the associated viewer route instead of calling `openFolder(url:)`.

Set `FolderSession.lastOpenedItemID` when opening a grid item and keep it valid through remove/replace operations.

- [ ] **Step 4: Run route tests and verify GREEN**

```bash
swift test --disable-sandbox --filter MainWindowControllerTests
swift test --disable-sandbox --filter FolderSessionTests
```

Expected: controller and folder-session tests pass; the scan count remains unchanged across live route switches.

- [ ] **Step 5: Commit route navigation**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Sources/ImageViewCore/Folder/FolderSession.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift Tests/ImageViewCoreTests/FolderSessionTests.swift
git commit -m "feat: add folder and viewer page navigation"
```

### Task 4: Add Hoverable Back, Forward, and Grid Controls

**Files:**
- Create: `Sources/ImageViewApp/Controls/HoverToolbarButton.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Create: `Tests/ImageViewAppTests/HoverToolbarButtonTests.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write failing control tests**

```swift
@MainActor
final class HoverToolbarButtonTests: XCTestCase {
    func testHoverAndPressChangeAppearanceWithoutChangingSize() {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        let size = button.frame.size

        button.setHoveredForTesting(true)
        XCTAssertTrue(button.testingShowsHover)
        XCTAssertEqual(button.frame.size, size)

        button.highlight(true)
        XCTAssertTrue(button.testingShowsPressed)
        XCTAssertEqual(button.frame.size, size)
    }

    func testDisabledButtonDoesNotShowHover() {
        let button = HoverToolbarButton()
        button.isEnabled = false
        button.setHoveredForTesting(true)
        XCTAssertFalse(button.testingShowsHover)
    }

    func testKeyboardFocusUsesFocusRingWithoutChangingSize() {
        let button = HoverToolbarButton()
        button.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        button.setFocusedForTesting(true)
        XCTAssertTrue(button.testingShowsFocus)
        XCTAssertEqual(button.frame.size, NSSize(width: 24, height: 24))
    }
}
```

Add a controller test asserting Back, Forward, and Grid exist, their enabled states track routes, and callbacks change routes.

- [ ] **Step 2: Run control tests and verify RED**

```bash
swift test --disable-sandbox --filter HoverToolbarButtonTests
swift test --disable-sandbox --filter MainWindowControllerTests/testTitleBarNavigationButtonsTrackRouteAvailability
```

Expected: compile failure because `HoverToolbarButton` and title-bar navigation test API do not exist.

- [ ] **Step 3: Implement the shared hover control**

Create a borderless `NSButton` subclass with `NSTrackingArea`, `mouseEntered`, `mouseExited`, and `highlight(_:)`. Use fixed constraints, `controlAccentColor.withAlphaComponent(0.12)` for hover, `0.20` for pressed, `cornerRadius = 6`, and `.secondaryLabelColor` for disabled symbols. Draw keyboard focus with `NSSetFocusRingStyle(.default)` from `drawFocusRingMask()` and never animate frame or constraints.

- [ ] **Step 4: Build and wire title-bar controls**

Replace `titleBarGridButton` with `HoverToolbarButton`, add Back (`chevron.backward`) and Forward (`chevron.forward`) buttons, and lay all three in a fixed-size horizontal `NSStackView`. Update enabled states whenever routes change. Keep title-bar double-click zoom on the bar background.

- [ ] **Step 5: Run focused tests and verify GREEN**

```bash
swift test --disable-sandbox --filter HoverToolbarButtonTests
swift test --disable-sandbox --filter MainWindowControllerTests
```

Expected: hover/control tests and all controller tests pass.

- [ ] **Step 6: Commit title-bar controls**

```bash
git add Sources/ImageViewApp/Controls Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/HoverToolbarButtonTests.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift
git commit -m "feat: add hoverable page navigation controls"
```

### Task 5: Localize, Integrate, and Verify

**Files:**
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/AppStringsTests.swift`

- [ ] **Step 1: Write failing localization tests**

Add the new keys to `titleBarKeys` and `folderBrowserKeys`, then assert exact Chinese and English values for Back, Forward, Show Folder, Show Image, Loading, Empty Folder, No Filter Results, Load Failed, Retry, Clear Filters, and Choose Another Folder.

- [ ] **Step 2: Run localization tests and verify RED**

```bash
swift test --disable-sandbox --filter AppStringsTests
```

Expected: failures show untranslated keys.

- [ ] **Step 3: Add localized strings and dynamic tooltips**

Add complete English and Simplified Chinese strings. Update Grid tooltip/accessibility text when the current route changes, and give Back/Forward localized tooltip and accessibility labels.

- [ ] **Step 4: Run the complete automated suite**

```bash
swift test --disable-sandbox
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Build and scan**

```bash
scripts/build-app.sh
/Users/zhupin/.codex/hooks/secret-scan.sh .
```

Expected: app build succeeds and secret scan reports no findings.

- [ ] **Step 6: Install and perform real UI verification**

```bash
scripts/install-app.sh
```

Relaunch `/Applications/ImageView.app`. Use read-only images under `/System/Library/Desktop Pictures` plus temporary empty/unmatched folders. Verify single-click selection without thumbnail blanking, double-click open, Grid toggle both directions, Back/Forward enabled states, hover/pressed feedback, filter clearing, empty folder, and retry/choose-folder recovery. Do not invoke Trash, Move, or Rename.

- [ ] **Step 7: Commit final integration**

```bash
git add Sources/ImageViewApp Tests/ImageViewAppTests
git commit -m "fix: complete folder browser navigation recovery"
```

- [ ] **Step 8: Push the completed main branch**

```bash
git push origin main
```

Expected: `main` and `origin/main` point to the same final commit.
