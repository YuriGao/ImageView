# Folder Browser Batch Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight current-folder browser with search, sorting, type filtering, multi-select, move-to-trash, move-to-folder, and batch rename while preserving ImageView's direct single-image viewer flow.

**Architecture:** Put reusable folder session and file mutation logic in `ImageViewCore`; keep AppKit grid UI, menus, panels, and titlebar actions in `ImageViewApp`. The existing single-image `ViewerViewModel` stays the image viewing owner; folder browsing is a sibling mode in `MainWindowController`, not a replacement for direct image opening.

**Tech Stack:** Swift 6, AppKit, Combine, UniformTypeIdentifiers, XCTest, Swift Package Manager.

---

## File Structure

- Create `Sources/ImageViewCore/Folder/FolderSortMode.swift`: sort modes and comparison helpers for folder sessions.
- Create `Sources/ImageViewCore/Folder/FolderFilter.swift`: search text and format filtering rules.
- Create `Sources/ImageViewCore/Folder/FolderSession.swift`: in-memory folder URL, item list, filter, sort, selection, and visible item projection.
- Create `Sources/ImageViewCore/Files/BatchFileOperationService.swift`: move-to-trash, move-to-folder, batch rename planning and execution.
- Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`: App-facing state wrapper around `FolderSession` and batch operation service.
- Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`: AppKit grid browser with toolbar controls.
- Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserCellView.swift`: thumbnail and filename grid cell.
- Create `Sources/ImageViewApp/FolderBrowser/BatchRenameSheetController.swift`: batch rename preview and validation UI.
- Create `Sources/ImageViewApp/FolderBrowser/ThumbnailProvider.swift`: asynchronous thumbnail generation for grid cells.
- Modify `Sources/ImageViewCore/Directory/DirectoryScanner.swift`: add folder scanning directly by folder URL.
- Modify `Sources/ImageViewApp/AppDelegate.swift`: add `Browse Folder...` menu and folder picker routing.
- Modify `Sources/ImageViewApp/MainWindowController.swift`: add browser mode, titlebar grid button, empty-state secondary browser action, and mode switching.
- Modify `Sources/ImageViewApp/Viewer/EmptyStateView.swift`: add optional secondary `Browse Folder...` action.
- Modify `Sources/ImageViewApp/Localization/AppStrings.swift` and localized strings: add menu and browser labels.
- Add focused tests under `Tests/ImageViewCoreTests/` and `Tests/ImageViewAppTests/`.

## Task 1: Core Folder Scanning and Session State

**Files:**
- Create: `Sources/ImageViewCore/Folder/FolderSortMode.swift`
- Create: `Sources/ImageViewCore/Folder/FolderFilter.swift`
- Create: `Sources/ImageViewCore/Folder/FolderSession.swift`
- Modify: `Sources/ImageViewCore/Directory/DirectoryScanner.swift`
- Test: `Tests/ImageViewCoreTests/FolderSessionTests.swift`
- Test: `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`

- [ ] **Step 1: Write failing folder scan test**

Add this test to `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`:

```swift
func testScansSupportedImagesInExplicitFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = root.appendingPathComponent("image-2.png")
    let second = root.appendingPathComponent("image-10.jpg")
    let ignored = root.appendingPathComponent("notes.txt")
    FileManager.default.createFile(atPath: first.path, contents: Data())
    FileManager.default.createFile(atPath: second.path, contents: Data())
    FileManager.default.createFile(atPath: ignored.path, contents: Data())

    let items = try await DirectoryScanner().scan(folder: root)

    XCTAssertEqual(items.map(\.url.lastPathComponent), ["image-2.png", "image-10.jpg"])
}
```

- [ ] **Step 2: Run focused test and verify RED**

```bash
swift test --disable-sandbox --filter DirectoryScannerTests/testScansSupportedImagesInExplicitFolder
```

Expected: compile failure because `scan(folder:)` does not exist.

- [ ] **Step 3: Add explicit folder scanning**

In `Sources/ImageViewCore/Directory/DirectoryScanner.swift`, extract the existing directory enumeration into a shared helper and add:

```swift
public func scan(folder directory: URL) async throws -> [ImageItem] {
    try await scanDirectory(directory)
}

private func scanDirectory(_ directory: URL) async throws -> [ImageItem] {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let urls = try self.fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                let items = urls.compactMap { url -> ImageItem? in
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true,
                          let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                        return nil
                    }
                    return ImageItem(url: url, format: format)
                }
                .sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
                continuation.resume(returning: items)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

Update `scan(containing:)` to call `scanDirectory(openedFile.deletingLastPathComponent())` and preserve the opened URL by replacing the matching item URL with `openedFile`.

- [ ] **Step 4: Write failing session projection tests**

Create `Tests/ImageViewCoreTests/FolderSessionTests.swift`:

```swift
import Foundation
import XCTest
@testable import ImageViewCore

final class FolderSessionTests: XCTestCase {
    func testVisibleItemsApplySearchFilterTypeFilterAndSort() {
        let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let items = [
            ImageItem(url: root.appendingPathComponent("b.PNG"), format: .png),
            ImageItem(url: root.appendingPathComponent("a.jpg"), format: .jpeg),
            ImageItem(url: root.appendingPathComponent("a-web.webp"), format: .webp)
        ]
        var session = FolderSession(folderURL: root, items: items)

        session.filter.searchText = "a"
        session.filter.allowedFormats = [.jpeg, .webp]
        session.sortMode = .nameAscending

        XCTAssertEqual(session.visibleItems.map(\.url.lastPathComponent), ["a-web.webp", "a.jpg"])
    }

    func testSelectionIsTrimmedToVisibleItemsAfterFiltering() {
        let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let first = ImageItem(url: root.appendingPathComponent("keep.png"), format: .png)
        let second = ImageItem(url: root.appendingPathComponent("hide.jpg"), format: .jpeg)
        var session = FolderSession(folderURL: root, items: [first, second])
        session.selectedItemIDs = Set([first.id, second.id])

        session.filter.allowedFormats = [.png]

        XCTAssertEqual(session.selectedItemIDs, Set([first.id]))
    }
}
```

- [ ] **Step 5: Run session tests and verify RED**

```bash
swift test --disable-sandbox --filter FolderSessionTests
```

Expected: compile failure because `FolderSession`, `FolderFilter`, and `FolderSortMode` do not exist.

- [ ] **Step 6: Implement folder session types**

Create `Sources/ImageViewCore/Folder/FolderSortMode.swift`:

```swift
import Foundation

public enum FolderSortMode: String, CaseIterable, Sendable, Equatable {
    case nameAscending
    case modifiedDateDescending
    case fileSizeDescending

    public func compare(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        switch self {
        case .nameAscending:
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        case .modifiedDateDescending:
            return resourceDate(lhs.url) > resourceDate(rhs.url)
        case .fileSizeDescending:
            return resourceSize(lhs.url) > resourceSize(rhs.url)
        }
    }

    private func resourceDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func resourceSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
```

Create `Sources/ImageViewCore/Folder/FolderFilter.swift`:

```swift
import Foundation

public struct FolderFilter: Equatable, Sendable {
    public var searchText: String
    public var allowedFormats: Set<SupportedImageFormat>

    public init(searchText: String = "", allowedFormats: Set<SupportedImageFormat> = Set(SupportedImageFormat.allCases)) {
        self.searchText = searchText
        self.allowedFormats = allowedFormats
    }

    public func includes(_ item: ImageItem) -> Bool {
        guard allowedFormats.contains(item.format) else { return false }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return item.url.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
    }
}
```

Create `Sources/ImageViewCore/Folder/FolderSession.swift`:

```swift
import Foundation

public struct FolderSession: Equatable, Sendable {
    public let folderURL: URL
    public var items: [ImageItem]
    public var filter: FolderFilter {
        didSet { trimSelectionToVisibleItems() }
    }
    public var sortMode: FolderSortMode
    public var selectedItemIDs: Set<ImageItem.ID>
    public var lastOpenedItemID: ImageItem.ID?

    public init(
        folderURL: URL,
        items: [ImageItem],
        filter: FolderFilter = FolderFilter(),
        sortMode: FolderSortMode = .nameAscending,
        selectedItemIDs: Set<ImageItem.ID> = []
    ) {
        self.folderURL = folderURL
        self.items = items
        self.filter = filter
        self.sortMode = sortMode
        self.selectedItemIDs = selectedItemIDs
        self.lastOpenedItemID = nil
        trimSelectionToVisibleItems()
    }

    public var visibleItems: [ImageItem] {
        items.filter(filter.includes).sorted(by: sortMode.compare)
    }

    public var selectedItems: [ImageItem] {
        visibleItems.filter { selectedItemIDs.contains($0.id) }
    }

    public mutating func removeItems(with ids: Set<ImageItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)
        trimSelectionToVisibleItems()
    }

    public mutating func replaceItems(_ replacements: [ImageItem.ID: ImageItem]) {
        items = items.map { replacements[$0.id] ?? $0 }
        selectedItemIDs = Set(selectedItemIDs.compactMap { replacements[$0]?.id ?? $0 })
        trimSelectionToVisibleItems()
    }

    private mutating func trimSelectionToVisibleItems() {
        let visibleIDs = Set(items.filter(filter.includes).map(\.id))
        selectedItemIDs = selectedItemIDs.intersection(visibleIDs)
    }
}
```

- [ ] **Step 7: Run core tests and commit**

```bash
swift test --disable-sandbox --filter DirectoryScannerTests
swift test --disable-sandbox --filter FolderSessionTests
git add Sources/ImageViewCore/Directory/DirectoryScanner.swift Sources/ImageViewCore/Folder Tests/ImageViewCoreTests/DirectoryScannerTests.swift Tests/ImageViewCoreTests/FolderSessionTests.swift
git commit -m "feat: add folder session model"
```

Expected: focused tests pass before commit.

## Task 2: Batch File Operation Service

**Files:**
- Create: `Sources/ImageViewCore/Files/BatchFileOperationService.swift`
- Test: `Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift`

- [ ] **Step 1: Write failing validation and execution tests**

Create `Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import ImageViewCore

final class BatchFileOperationServiceTests: XCTestCase {
    func testRenamePlanPreservesExtensionsAndRejectsConflicts() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeFile("old-a.png", in: root)
        let second = try makeFile("old-b.jpg", in: root)
        _ = try makeFile("Photo 01.png", in: root)

        let service = BatchFileOperationService()
        let result = service.planBatchRename(urls: [first, second], baseName: "Photo", startNumber: 1, padding: 2)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.url == first && $0.reason == .destinationExists })
        XCTAssertEqual(result.proposedRenames.map { $0.destination.lastPathComponent }, ["Photo 01.png", "Photo 02.jpg"])
    }

    func testMoveToFolderSkipsConflictsWithoutOverwriting() throws {
        let source = try makeTempFolder()
        let destination = try makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let original = try makeFile("same.png", in: source, contents: "source")
        _ = try makeFile("same.png", in: destination, contents: "destination")

        let result = try BatchFileOperationService().moveToFolder([original], destinationFolder: destination, conflictPolicy: .skip)

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(String(data: try Data(contentsOf: destination.appendingPathComponent("same.png")), encoding: .utf8), "destination")
    }

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, in folder: URL, contents: String = "x") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --disable-sandbox --filter BatchFileOperationServiceTests
```

Expected: compile failure because `BatchFileOperationService` does not exist.

- [ ] **Step 3: Implement batch service**

Create `Sources/ImageViewCore/Files/BatchFileOperationService.swift`:

```swift
import Foundation

public enum BatchFileFailureReason: Equatable, Sendable {
    case emptyName
    case invalidName
    case duplicateDestination
    case destinationExists
    case sourceMissing
    case fileSystem(String)
}

public enum MoveConflictPolicy: Equatable, Sendable {
    case skip
    case keepBoth
}

public struct BatchFileFailure: Equatable, Sendable {
    public let url: URL
    public let reason: BatchFileFailureReason
}

public struct BatchOperationResult: Equatable, Sendable {
    public var succeeded: [URL]
    public var failed: [BatchFileFailure]

    public init(succeeded: [URL] = [], failed: [BatchFileFailure] = []) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

public struct RenameProposal: Equatable, Sendable {
    public let source: URL
    public let destination: URL
}

public struct BatchRenamePlan: Equatable, Sendable {
    public let proposedRenames: [RenameProposal]
    public let errors: [BatchFileFailure]
    public var isValid: Bool { errors.isEmpty }
}

public final class BatchFileOperationService: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(_ urls: [URL]) -> BatchOperationResult {
        var result = BatchOperationResult()
        for url in urls {
            do {
                var trashedURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
                result.succeeded.append(url)
            } catch {
                result.failed.append(BatchFileFailure(url: url, reason: .fileSystem(error.localizedDescription)))
            }
        }
        return result
    }

    public func moveToFolder(_ urls: [URL], destinationFolder: URL, conflictPolicy: MoveConflictPolicy) throws -> BatchOperationResult {
        var result = BatchOperationResult()
        for source in urls {
            guard fileManager.fileExists(atPath: source.path) else {
                result.failed.append(BatchFileFailure(url: source, reason: .sourceMissing))
                continue
            }
            let destination = destinationURL(for: source.lastPathComponent, in: destinationFolder, conflictPolicy: conflictPolicy)
            guard let destination else {
                result.failed.append(BatchFileFailure(url: source, reason: .destinationExists))
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                result.succeeded.append(source)
            } catch {
                result.failed.append(BatchFileFailure(url: source, reason: .fileSystem(error.localizedDescription)))
            }
        }
        return result
    }

    public func planBatchRename(urls: [URL], baseName: String, startNumber: Int, padding: Int) -> BatchRenamePlan {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return BatchRenamePlan(proposedRenames: [], errors: urls.map { BatchFileFailure(url: $0, reason: .emptyName) })
        }
        guard isValidBaseName(trimmed) else {
            return BatchRenamePlan(proposedRenames: [], errors: urls.map { BatchFileFailure(url: $0, reason: .invalidName) })
        }

        let proposals = urls.enumerated().map { index, source in
            let number = String(format: "%0\(max(1, padding))d", startNumber + index)
            let destination = source.deletingLastPathComponent()
                .appendingPathComponent("\(trimmed) \(number)")
                .appendingPathExtension(source.pathExtension)
            return RenameProposal(source: source, destination: destination)
        }
        var errors: [BatchFileFailure] = []
        let grouped = Dictionary(grouping: proposals, by: \.destination.standardizedFileURL)
        for duplicate in grouped.values where duplicate.count > 1 {
            errors.append(contentsOf: duplicate.map { BatchFileFailure(url: $0.source, reason: .duplicateDestination) })
        }
        let selectedSources = Set(urls.map(\.standardizedFileURL))
        for proposal in proposals where fileManager.fileExists(atPath: proposal.destination.path) && !selectedSources.contains(proposal.destination.standardizedFileURL) {
            errors.append(BatchFileFailure(url: proposal.source, reason: .destinationExists))
        }
        return BatchRenamePlan(proposedRenames: proposals, errors: errors)
    }

    public func executeRenamePlan(_ plan: BatchRenamePlan) -> BatchOperationResult {
        guard plan.isValid else {
            return BatchOperationResult(failed: plan.errors)
        }
        var result = BatchOperationResult()
        let temporaryRenames = plan.proposedRenames.map { proposal in
            RenameProposal(
                source: proposal.source,
                destination: proposal.source.deletingLastPathComponent().appendingPathComponent(".imageview-\(UUID().uuidString).\(proposal.source.pathExtension)")
            )
        }
        do {
            for proposal in temporaryRenames {
                try fileManager.moveItem(at: proposal.source, to: proposal.destination)
            }
            for (temporary, final) in zip(temporaryRenames, plan.proposedRenames) {
                try fileManager.moveItem(at: temporary.destination, to: final.destination)
                result.succeeded.append(final.source)
            }
        } catch {
            result.failed.append(BatchFileFailure(url: plan.proposedRenames.first?.source ?? URL(fileURLWithPath: "/"), reason: .fileSystem(error.localizedDescription)))
        }
        return result
    }

    private func destinationURL(for filename: String, in folder: URL, conflictPolicy: MoveConflictPolicy) -> URL? {
        let base = folder.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: base.path) else { return base }
        guard conflictPolicy == .keepBoth else { return nil }
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        for index in 2...9999 {
            let candidate = folder.appendingPathComponent("\(stem) \(index)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func isValidBaseName(_ name: String) -> Bool {
        name != "." && name != ".." && !name.contains("/") && !name.contains(":")
    }
}
```

- [ ] **Step 4: Add execute-rename collision test**

Add to `BatchFileOperationServiceTests`:

```swift
func testExecuteRenamePlanHandlesIntraSelectionSwap() throws {
    let root = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try makeFile("Photo 01.png", in: root)
    let second = try makeFile("Photo 02.png", in: root)

    let service = BatchFileOperationService()
    let plan = BatchRenamePlan(
        proposedRenames: [
            RenameProposal(source: first, destination: root.appendingPathComponent("Photo 02.png")),
            RenameProposal(source: second, destination: root.appendingPathComponent("Photo 01.png"))
        ],
        errors: []
    )

    let result = service.executeRenamePlan(plan)

    XCTAssertEqual(result.failed.count, 0)
    XCTAssertEqual(result.succeeded.count, 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photo 01.png").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Photo 02.png").path))
}
```

- [ ] **Step 5: Run focused tests and commit**

```bash
swift test --disable-sandbox --filter BatchFileOperationServiceTests
git add Sources/ImageViewCore/Files/BatchFileOperationService.swift Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift
git commit -m "feat: add batch file operations"
```

Expected: focused tests pass before commit.

## Task 3: Folder Browser View Model

**Files:**
- Create: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Test: `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`:

```swift
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class FolderBrowserViewModelTests: XCTestCase {
    func testOpenFolderLoadsSessionAndSelectsNothing() async {
        let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let item = ImageItem(url: root.appendingPathComponent("a.png"), format: .png)
        let viewModel = FolderBrowserViewModel(scanFolder: { folder in
            XCTAssertEqual(folder, root)
            return [item]
        })

        await viewModel.openFolder(root)

        XCTAssertEqual(viewModel.session?.folderURL, root)
        XCTAssertEqual(viewModel.visibleItems, [item])
        XCTAssertTrue(viewModel.selectedItems.isEmpty)
    }

    func testSearchTextUpdatesVisibleItems() async {
        let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let items = [
            ImageItem(url: root.appendingPathComponent("keep.png"), format: .png),
            ImageItem(url: root.appendingPathComponent("hide.jpg"), format: .jpeg)
        ]
        let viewModel = FolderBrowserViewModel(scanFolder: { _ in items })

        await viewModel.openFolder(root)
        viewModel.searchText = "keep"

        XCTAssertEqual(viewModel.visibleItems.map(\.url.lastPathComponent), ["keep.png"])
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --disable-sandbox --filter FolderBrowserViewModelTests
```

Expected: compile failure because `FolderBrowserViewModel` does not exist.

- [ ] **Step 3: Implement view model shell**

Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`:

```swift
import Combine
import Foundation
import ImageViewCore

@MainActor
final class FolderBrowserViewModel: ObservableObject {
    @Published private(set) var session: FolderSession?
    @Published private(set) var isLoading = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationFailures: [BatchFileFailure] = []

    private let scanFolder: (URL) async throws -> [ImageItem]
    private let operations: BatchFileOperationService

    init(
        scanFolder: @escaping (URL) async throws -> [ImageItem] = { try await DirectoryScanner().scan(folder: $0) },
        operations: BatchFileOperationService = BatchFileOperationService()
    ) {
        self.scanFolder = scanFolder
        self.operations = operations
    }

    var visibleItems: [ImageItem] {
        session?.visibleItems ?? []
    }

    var selectedItems: [ImageItem] {
        session?.selectedItems ?? []
    }

    var searchText: String {
        get { session?.filter.searchText ?? "" }
        set { session?.filter.searchText = newValue }
    }

    func openFolder(_ folderURL: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await scanFolder(folderURL)
            session = FolderSession(folderURL: folderURL, items: items)
            operationMessage = nil
            operationFailures = []
        } catch {
            session = FolderSession(folderURL: folderURL, items: [])
            operationMessage = error.localizedDescription
            operationFailures = []
        }
    }

    func setSelectedItemIDs(_ ids: Set<ImageItem.ID>) {
        session?.selectedItemIDs = ids
    }

    func setSortMode(_ sortMode: FolderSortMode) {
        session?.sortMode = sortMode
    }

    func setAllowedFormats(_ formats: Set<SupportedImageFormat>) {
        session?.filter.allowedFormats = formats
    }
}
```

- [ ] **Step 4: Add batch operation view model tests**

Add to `FolderBrowserViewModelTests.swift`:

```swift
func testApplyingTrashResultRemovesSucceededAndKeepsFailedSelected() async {
    let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
    let keep = ImageItem(url: root.appendingPathComponent("keep.png"), format: .png)
    let remove = ImageItem(url: root.appendingPathComponent("remove.png"), format: .png)
    let viewModel = FolderBrowserViewModel(scanFolder: { _ in [keep, remove] })
    await viewModel.openFolder(root)
    viewModel.setSelectedItemIDs(Set([keep.id, remove.id]))

    viewModel.applyOperationResult(
        BatchOperationResult(
            succeeded: [remove.url],
            failed: [BatchFileFailure(url: keep.url, reason: .fileSystem("denied"))]
        ),
        removingSucceeded: true
    )

    XCTAssertEqual(viewModel.visibleItems, [keep])
    XCTAssertEqual(viewModel.selectedItems, [keep])
    XCTAssertEqual(viewModel.operationFailures.count, 1)
}
```

- [ ] **Step 5: Implement result application**

Add to `FolderBrowserViewModel`:

```swift
func applyOperationResult(_ result: BatchOperationResult, removingSucceeded: Bool) {
    operationFailures = result.failed
    operationMessage = "已处理 \(result.succeeded.count) 个，失败 \(result.failed.count) 个"
    guard var session else { return }
    let succeededIDs = Set(result.succeeded.map(\.standardizedFileURL))
    if removingSucceeded {
        session.removeItems(with: succeededIDs)
    }
    session.selectedItemIDs = Set(result.failed.map(\.url.standardizedFileURL))
    self.session = session
}
```

- [ ] **Step 6: Run focused tests and commit**

```bash
swift test --disable-sandbox --filter FolderBrowserViewModelTests
git add Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift
git commit -m "feat: add folder browser view model"
```

Expected: focused tests pass before commit.

## Task 4: Folder Browser UI and Thumbnail Provider

**Files:**
- Create: `Sources/ImageViewApp/FolderBrowser/ThumbnailProvider.swift`
- Create: `Sources/ImageViewApp/FolderBrowser/FolderBrowserCellView.swift`
- Create: `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`
- Test: `Tests/ImageViewAppTests/ThumbnailProviderTests.swift`
- Test: `Tests/ImageViewAppTests/FolderBrowserViewTests.swift`

- [ ] **Step 1: Write failing thumbnail provider test**

Create `Tests/ImageViewAppTests/ThumbnailProviderTests.swift`:

```swift
import AppKit
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class ThumbnailProviderTests: XCTestCase {
    func testCancellingThumbnailRequestPreventsCompletion() async {
        let provider = ThumbnailProvider(loadThumbnail: { _, _ in
            try await Task.sleep(nanoseconds: 200_000_000)
            return NSImage(size: NSSize(width: 10, height: 10))
        })
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        var completed = false

        let request = provider.requestThumbnail(for: item, maxPixelSize: 160) { _ in completed = true }
        request.cancel()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(completed)
    }
}
```

- [ ] **Step 2: Implement thumbnail provider**

Create `Sources/ImageViewApp/FolderBrowser/ThumbnailProvider.swift`:

```swift
import AppKit
import ImageViewCore

@MainActor
final class ThumbnailRequestToken {
    private let cancelHandler: () -> Void

    init(cancelHandler: @escaping () -> Void) {
        self.cancelHandler = cancelHandler
    }

    func cancel() {
        cancelHandler()
    }
}

@MainActor
final class ThumbnailProvider {
    private let loadThumbnail: (URL, SupportedImageFormat) async throws -> NSImage

    init(loadThumbnail: @escaping (URL, SupportedImageFormat) async throws -> NSImage = ThumbnailProvider.defaultThumbnail) {
        self.loadThumbnail = loadThumbnail
    }

    func requestThumbnail(for item: ImageItem, maxPixelSize: CGFloat, completion: @escaping (NSImage?) -> Void) -> ThumbnailRequestToken {
        let task = Task { [loadThumbnail] in
            let image = try? await loadThumbnail(item.url, item.format)
            guard !Task.isCancelled else { return }
            completion(image)
        }
        return ThumbnailRequestToken { task.cancel() }
    }

    private static func defaultThumbnail(url: URL, format: SupportedImageFormat) async throws -> NSImage {
        let decoded = try await Task.detached(priority: .utility) {
            try ImageDecodeService().decode(url: url, format: format, maxPixelSize: 320)
        }.value
        return NSImage(cgImage: decoded.cgImage, size: decoded.pixelSize)
    }
}
```

- [ ] **Step 3: Write failing view tests**

Create `Tests/ImageViewAppTests/FolderBrowserViewTests.swift`:

```swift
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class FolderBrowserViewTests: XCTestCase {
    func testBrowserViewExposesToolbarControlsForTesting() {
        let view = FolderBrowserView()

        XCTAssertEqual(view.searchFieldPlaceholderForTesting, "搜索文件名")
        XCTAssertTrue(view.hasSortControlForTesting)
        XCTAssertTrue(view.hasTypeFilterControlForTesting)
        XCTAssertTrue(view.hasMoveToTrashButtonForTesting)
        XCTAssertTrue(view.hasMoveToFolderButtonForTesting)
        XCTAssertTrue(view.hasRenameButtonForTesting)
    }
}
```

- [ ] **Step 4: Implement browser cell and grid shell**

Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserCellView.swift` with an `NSImageView` and filename `NSTextField`. Create `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift` with:

```swift
import AppKit
import ImageViewCore

final class FolderBrowserView: NSView {
    var onOpenItem: ((ImageItem) -> Void)?
    var onSelectionChanged: ((Set<ImageItem.ID>) -> Void)?
    var onSearchChanged: ((String) -> Void)?
    var onMoveToTrash: (() -> Void)?
    var onMoveToFolder: (() -> Void)?
    var onBatchRename: (() -> Void)?

    private let searchField = NSSearchField()
    private let sortControl = NSPopUpButton()
    private let typeFilterControl = NSPopUpButton()
    private let moveToTrashButton = NSButton()
    private let moveToFolderButton = NSButton()
    private let renameButton = NSButton()
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        searchField.placeholderString = "搜索文件名"
        sortControl.addItems(withTitles: ["名称", "修改时间", "文件大小"])
        typeFilterControl.addItems(withTitles: ["全部格式"] + SupportedImageFormat.allCases.map(\.rawValue.uppercased))
        configureButton(moveToTrashButton, title: "移到废纸篓", action: #selector(requestMoveToTrash(_:)))
        configureButton(moveToFolderButton, title: "移动到…", action: #selector(requestMoveToFolder(_:)))
        configureButton(renameButton, title: "重命名…", action: #selector(requestBatchRename(_:)))
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(items: [ImageItem], selectedIDs: Set<ImageItem.ID>) {
        // Use NSCollectionView data source in the implementation; keep this method as the only rendering entry point.
    }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private func buildLayout() {
        let toolbar = NSStackView(views: [searchField, sortControl, typeFilterControl, moveToTrashButton, moveToFolderButton, renameButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func requestMoveToTrash(_ sender: Any?) { onMoveToTrash?() }
    @objc private func requestMoveToFolder(_ sender: Any?) { onMoveToFolder?() }
    @objc private func requestBatchRename(_ sender: Any?) { onBatchRename?() }

    var searchFieldPlaceholderForTesting: String? { searchField.placeholderString }
    var hasSortControlForTesting: Bool { sortControl.numberOfItems > 0 }
    var hasTypeFilterControlForTesting: Bool { typeFilterControl.numberOfItems > 0 }
    var hasMoveToTrashButtonForTesting: Bool { moveToTrashButton.superview != nil }
    var hasMoveToFolderButtonForTesting: Bool { moveToFolderButton.superview != nil }
    var hasRenameButtonForTesting: Bool { renameButton.superview != nil }
}
```

Then replace the `apply` placeholder with a real `NSCollectionViewDiffableDataSource` or an existing AppKit collection-view pattern. Keep selection callbacks and double-click callbacks in this view; do not mutate files here.

- [ ] **Step 5: Run focused tests and commit**

```bash
swift test --disable-sandbox --filter ThumbnailProviderTests
swift test --disable-sandbox --filter FolderBrowserViewTests
git add Sources/ImageViewApp/FolderBrowser Tests/ImageViewAppTests/ThumbnailProviderTests.swift Tests/ImageViewAppTests/FolderBrowserViewTests.swift
git commit -m "feat: add folder browser view"
```

Expected: focused tests pass before commit.

## Task 5: Window, Menu, and Empty-State Integration

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewApp/Viewer/EmptyStateView.swift`
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ImageViewAppTests/AppDelegateTests.swift`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`
- Test: `Tests/ImageViewAppTests/EmptyStateViewTests.swift`

- [ ] **Step 1: Add failing empty-state secondary action test**

Add to `Tests/ImageViewAppTests/EmptyStateViewTests.swift`:

```swift
func testBrowseFolderButtonCanInvokeSecondaryCallback() {
    let view = EmptyStateView(preferredLanguages: ["zh-Hans"])
    var count = 0
    view.onBrowseFolderRequested = { count += 1 }

    view.performBrowseFolderForTesting()

    XCTAssertEqual(count, 1)
    XCTAssertEqual(view.browseFolderButtonTitleForTesting, "浏览文件夹…")
}
```

- [ ] **Step 2: Implement empty-state secondary action**

In `Sources/ImageViewApp/Viewer/EmptyStateView.swift`, add:

```swift
var onBrowseFolderRequested: (() -> Void)?
private let browseFolderButton = NSButton()

@objc private func requestBrowseFolder(_ sender: Any?) {
    onBrowseFolderRequested?()
}

var browseFolderButtonTitleForTesting: String { browseFolderButton.title }
func performBrowseFolderForTesting() { requestBrowseFolder(nil) }
```

Configure the button with `emptyState.browseFolder` and add it to the existing vertical stack below the open button.

- [ ] **Step 3: Add failing folder picker menu test**

Add to `Tests/ImageViewAppTests/AppDelegateTests.swift`:

```swift
func testFileMenuContainsBrowseFolderCommand() {
    let delegate = AppDelegate(settings: AppSettings(defaults: makeIsolatedDefaults()))
    let menu = delegate.makeMainMenu(preferredLanguages: ["en"])

    let fileMenu = menu.items[1].submenu

    XCTAssertNotNil(fileMenu?.item(withTitle: "Browse Folder..."))
}
```

- [ ] **Step 4: Add folder picker routing**

In `AppDelegate`, add a `chooseFolderURL` dependency:

```swift
private let chooseFolderURL: () -> URL?
private let openFolderURL: (MainWindowController, URL) -> Void
```

Default implementations:

```swift
chooseFolderURL: @escaping () -> URL? = {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
},
openFolderURL: @escaping (MainWindowController, URL) -> Void = { $0.openFolder(url: $1) }
```

Add `Browse Folder...` to the File menu after `Open...` and route it through:

```swift
@objc private func browseFolder(_ sender: Any?) {
    requestBrowseFolder(requesting: menuTargetImageController)
}

private func requestBrowseFolder(requesting controller: MainWindowController? = nil) {
    guard let url = chooseFolderURL() else { return }
    let target = controller ?? activeImageWindowController ?? createImageWindow()
    activeImageWindowController = target
    openFolderURL(target, url)
    showImageWindow(target)
}
```

- [ ] **Step 5: Add failing browser mode visibility test**

Add to `Tests/ImageViewAppTests/MainWindowControllerTests.swift`:

```swift
func testOpeningFolderShowsFolderBrowserAndHidesImageOnlyStatus() async {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

    await controller.openFolderForTesting(URL(fileURLWithPath: "/tmp/images", isDirectory: true), items: [])

    XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
}
```

- [ ] **Step 6: Integrate browser mode in MainWindowController**

In `MainWindowController`, add:

```swift
private enum ContentMode {
    case viewer
    case folderBrowser
}

private let folderBrowserViewModel = FolderBrowserViewModel()
private let folderBrowserView = FolderBrowserView()
private let folderToggleButton = NSButton()
private var contentMode: ContentMode = .viewer
```

Add `folderBrowserView` as a sibling of `canvas`, `emptyStateView`, and `errorStateView`, constrained to the canvas area. Add a compact titlebar button with `square.grid.2x2`.

Implement:

```swift
func openFolder(url: URL) {
    hasAssignedOpenRequest = true
    cancelCrop(nil)
    contentMode = .folderBrowser
    Task { await folderBrowserViewModel.openFolder(url) }
    updateContentModePresentation()
}

private func updateContentModePresentation() {
    let showingFolder = contentMode == .folderBrowser
    folderBrowserView.isHidden = !showingFolder
    canvas.isHidden = showingFolder
    emptyStateView.isHidden = showingFolder || !emptyStateView.isHidden
    errorStateView.isHidden = showingFolder || !errorStateView.isHidden
    bottomDimensionLabel.isHidden = showingFolder
    bottomPageLabel.isHidden = showingFolder
    bottomZoomLabel.isHidden = showingFolder
    bottomInfoButton.isHidden = showingFolder
}
```

When `folderBrowserView.onOpenItem` fires, call `open(url:)` and set `contentMode = .viewer`. When the titlebar grid button is clicked while viewing an image, open that image's containing folder and preserve the current image URL in `FolderSession.lastOpenedItemID`.

- [ ] **Step 7: Wire empty-state browse callback**

In `setup()`:

```swift
emptyStateView.onBrowseFolderRequested = { [weak self] in
    self?.onBrowseFolderRequested?()
}
```

Add `var onBrowseFolderRequested: (() -> Void)?` to `MainWindowController`, and bind it from `AppDelegate.createImageWindow()` to `requestBrowseFolder(requesting:)`.

- [ ] **Step 8: Run focused tests and commit**

```bash
swift test --disable-sandbox --filter EmptyStateViewTests
swift test --disable-sandbox --filter AppDelegateTests/testFileMenuContainsBrowseFolderCommand
swift test --disable-sandbox --filter MainWindowControllerTests/testOpeningFolderShowsFolderBrowserAndHidesImageOnlyStatus
git add Sources/ImageViewApp/AppDelegate.swift Sources/ImageViewApp/MainWindowController.swift Sources/ImageViewApp/Viewer/EmptyStateView.swift Sources/ImageViewApp/Localization/AppStrings.swift Sources/ImageViewApp/Resources/en.lproj/Localizable.strings Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings Tests/ImageViewAppTests/AppDelegateTests.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift Tests/ImageViewAppTests/EmptyStateViewTests.swift
git commit -m "feat: integrate folder browser mode"
```

Expected: focused tests pass before commit.

## Task 6: Batch Rename Sheet and User-Facing Operations

**Files:**
- Create: `Sources/ImageViewApp/FolderBrowser/BatchRenameSheetController.swift`
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Test: `Tests/ImageViewAppTests/BatchRenameSheetControllerTests.swift`
- Test: `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing rename sheet test**

Create `Tests/ImageViewAppTests/BatchRenameSheetControllerTests.swift`:

```swift
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class BatchRenameSheetControllerTests: XCTestCase {
    func testPreviewDisplaysOldToNewNames() {
        let root = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let items = [
            ImageItem(url: root.appendingPathComponent("old-a.png"), format: .png),
            ImageItem(url: root.appendingPathComponent("old-b.jpg"), format: .jpeg)
        ]
        let controller = BatchRenameSheetController(items: items)

        controller.setBaseNameForTesting("Photo")
        controller.setStartNumberForTesting(1)
        controller.setPaddingForTesting(2)

        XCTAssertEqual(controller.previewRowsForTesting, ["old-a.png -> Photo 01.png", "old-b.jpg -> Photo 02.jpg"])
    }
}
```

- [ ] **Step 2: Implement rename sheet controller**

Create `Sources/ImageViewApp/FolderBrowser/BatchRenameSheetController.swift` as an `NSWindowController` with:

```swift
import AppKit
import ImageViewCore

@MainActor
final class BatchRenameSheetController: NSWindowController {
    private let items: [ImageItem]
    private let baseNameField = NSTextField(string: "")
    private let startNumberField = NSTextField(string: "1")
    private let paddingField = NSTextField(string: "2")
    private let previewLabel = NSTextField(labelWithString: "")
    var onConfirm: ((String, Int, Int) -> Void)?

    init(items: [ImageItem]) {
        self.items = items
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 280), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        buildContent()
        updatePreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func buildContent() {
        window?.title = "批量重命名"
        baseNameField.stringValue = "Image"
        let confirm = NSButton(title: "重命名", target: self, action: #selector(confirmRename(_:)))
        let stack = NSStackView(views: [baseNameField, startNumberField, paddingField, previewLabel, confirm])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = NSView()
        window?.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 16)
        ])
    }

    private func updatePreview() {
        previewLabel.stringValue = previewRowsForTesting.prefix(5).joined(separator: "\n")
    }

    @objc private func confirmRename(_ sender: Any?) {
        onConfirm?(baseNameField.stringValue, Int(startNumberField.stringValue) ?? 1, Int(paddingField.stringValue) ?? 1)
    }

    var previewRowsForTesting: [String] {
        let base = baseNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Int(startNumberField.stringValue) ?? 1
        let padding = Int(paddingField.stringValue) ?? 1
        return items.enumerated().map { index, item in
            let number = String(format: "%0\(padding)d", start + index)
            let newName = "\(base) \(number).\(item.url.pathExtension)"
            return "\(item.url.lastPathComponent) -> \(newName)"
        }
    }

    func setBaseNameForTesting(_ value: String) { baseNameField.stringValue = value; updatePreview() }
    func setStartNumberForTesting(_ value: Int) { startNumberField.stringValue = "\(value)"; updatePreview() }
    func setPaddingForTesting(_ value: Int) { paddingField.stringValue = "\(value)"; updatePreview() }
}
```

Refine layout and validation display during implementation, but keep preview generation covered by tests.

- [ ] **Step 3: Add selected operation methods to view model**

In `FolderBrowserViewModel`, add:

```swift
func moveSelectedToTrash() {
    let result = operations.moveToTrash(selectedItems.map(\.url))
    applyOperationResult(result, removingSucceeded: true)
}

func moveSelected(to destinationFolder: URL, conflictPolicy: MoveConflictPolicy) {
    do {
        let result = try operations.moveToFolder(selectedItems.map(\.url), destinationFolder: destinationFolder, conflictPolicy: conflictPolicy)
        applyOperationResult(result, removingSucceeded: true)
    } catch {
        operationMessage = error.localizedDescription
    }
}

func renameSelected(baseName: String, startNumber: Int, padding: Int) {
    let plan = operations.planBatchRename(urls: selectedItems.map(\.url), baseName: baseName, startNumber: startNumber, padding: padding)
    let result = operations.executeRenamePlan(plan)
    if result.failed.isEmpty {
        Task { [weak self] in
            guard let folderURL = self?.session?.folderURL else { return }
            await self?.openFolder(folderURL)
        }
    } else {
        applyOperationResult(result, removingSucceeded: false)
    }
}
```

- [ ] **Step 4: Wire confirmations and panels in MainWindowController**

For folder browser callbacks:

```swift
folderBrowserView.onMoveToTrash = { [weak self] in self?.confirmAndMoveSelectedBrowserItemsToTrash() }
folderBrowserView.onMoveToFolder = { [weak self] in self?.chooseDestinationAndMoveSelectedBrowserItems() }
folderBrowserView.onBatchRename = { [weak self] in self?.showBatchRenameSheet() }
```

Implement confirm dialogs with selected count, destination folder picker, conflict policy alert, and rename sheet. Keep all dialogs in `MainWindowController`; keep file operations in `FolderBrowserViewModel`.

- [ ] **Step 5: Run focused tests and commit**

```bash
swift test --disable-sandbox --filter BatchRenameSheetControllerTests
swift test --disable-sandbox --filter FolderBrowserViewModelTests
git add Sources/ImageViewApp/FolderBrowser Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/BatchRenameSheetControllerTests.swift Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift
git commit -m "feat: add folder batch actions"
```

Expected: focused tests pass before commit.

## Task 7: Localization, Full Test Run, and Manual Verification

**Files:**
- Modify as needed: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify as needed: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify as needed: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Optionally modify: `README.md` only after the feature is implemented and verified.

- [ ] **Step 1: Add localization coverage test**

Add the new keys to `AppStrings.menuKeys`, `emptyStateKeys`, and a new `folderBrowserKeys` list. Extend `Tests/ImageViewAppTests/AppStringsTests.swift` so every new key resolves in English and Chinese.

Use keys:

```swift
"menu.file.browseFolder"
"emptyState.browseFolder"
"folderBrowser.searchPlaceholder"
"folderBrowser.sort.name"
"folderBrowser.sort.modifiedDate"
"folderBrowser.sort.fileSize"
"folderBrowser.filter.allFormats"
"folderBrowser.moveToTrash"
"folderBrowser.moveToFolder"
"folderBrowser.rename"
"folderBrowser.renameTitle"
"folderBrowser.renameConfirm"
```

- [ ] **Step 2: Run all tests**

```bash
swift test --disable-sandbox
```

Expected: all tests pass.

- [ ] **Step 3: Build the app bundle**

```bash
scripts/build-app.sh
```

Expected: `.build/ImageView.app` is produced without build errors.

- [ ] **Step 4: Manual verification checklist**

Run the app:

```bash
open .build/ImageView.app
```

Verify:

- Empty state shows both `Open Image...` and `Browse Folder...`.
- `File > Browse Folder...` opens a folder picker.
- Opening a folder with JPEG, PNG, HEIC, WebP, SVG, and TXT files shows only supported image formats.
- Filename search filters the grid.
- Sort by name, modified date, and file size changes ordering.
- Type filter narrows visible items.
- Command-click, Shift-click, and Command-A multi-select items.
- Double-click or Return opens the image in viewer mode.
- Returning to grid preserves selection and approximate scroll position.
- Move to Trash asks for confirmation and removes successful files from the grid.
- Move to Folder does not overwrite same-name destination files.
- Batch rename preview shows old name to new name and preserves extensions.
- Batch rename blocks duplicates and existing unselected destination names.
- Failed operations keep failed files selected and allow continued browsing.
- Existing direct Finder double-click and `Open...` image paths still open single images directly.

- [ ] **Step 5: Optional README update after verification**

If the manual checklist passes, update `README.md` current features with one bullet:

```markdown
- 文件夹浏览模式支持按文件名搜索、按格式过滤、排序、多选、批量移到废纸篓、移动到文件夹和批量重命名。
```

- [ ] **Step 6: Final commit**

```bash
git add Sources Tests README.md
git commit -m "feat: add folder browser batch organization"
```

Expected: commit includes implementation, tests, and README only if the feature passed verification.

## Scope Guardrails

- Do not add a persistent library database.
- Do not recursively scan folders.
- Do not silently overwrite files.
- Do not add ratings, tags, albums, people, timeline, conversion, compression, resizing, watermarking, or permanent delete in this implementation.
- Do not change direct image opening into a mandatory folder browser flow.
- Do not mix file mutation logic into AppKit views.

## Self-Review Notes

- Spec coverage: folder session, entry points, grid, multi-select, search, sorting, type filtering, batch trash, move, rename, error recovery, compatibility, and testing are each mapped to tasks.
- Placeholder scan: the plan avoids open-ended placeholders and gives concrete files, commands, and expected results.
- Type consistency: Core types introduced in Tasks 1 and 2 are used by later App tasks with matching names.
