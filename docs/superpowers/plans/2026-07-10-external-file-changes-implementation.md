# External File Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover gracefully when the current image is deleted or changed outside ImageView.

**Architecture:** `ViewerViewModel` owns version capture, cache invalidation, navigation updates, and user-facing errors. `MainWindowController` merely requests a refresh when the window regains focus or navigation begins. Resource versions use Foundation file attributes so the behavior is testable through an injected reader.

**Tech Stack:** Swift 6, Foundation, AppKit, XCTest, SwiftPM.

## Global Constraints

- Keep all filesystem work off the rendering path except the small version attribute lookup.
- Never discard `hasUnsavedEdits` because an external file changed.
- Preserve the existing navigation and error-overlay conventions.

---

### Task 1: Add view-model regression tests

**Files:**
- Modify: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`

**Interfaces:**
- Produces `func refreshCurrentFileIfNeeded() async` on `ViewerViewModel`.
- Adds an injectable resource-version reader returning `CurrentFileVersion?`.

- [ ] **Step 1: Write failing tests**

```swift
func testRefreshRemovesExternallyDeletedCurrentItemAndLoadsNextImage() async throws {
    // Open two items, return nil for the first file version, refresh, then assert the second is current.
}

func testRefreshReloadsCurrentImageWhenExternalVersionChanges() async throws {
    // Return version one on open, version two on refresh, and assert the decoder returns the replacement image.
}
```

- [ ] **Step 2: Run the focused test target to verify failure**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ViewerViewModelTests`

Expected: the tests fail because `refreshCurrentFileIfNeeded()` does not exist.

- [ ] **Step 3: Implement the minimal view-model refresh path**

```swift
func refreshCurrentFileIfNeeded() async {
    guard let item = navigationState?.currentItem else { return }
    guard let version = currentFileVersion(item.url) else { removeUnavailableCurrentItem(item); return }
    guard version != displayedFileVersion else { return }
    guard !hasUnsavedEdits else { errorMessage = externalChangeMessage(item); return }
    await reloadChangedCurrentItem(item, version: version)
}
```

- [ ] **Step 4: Run focused tests to verify pass**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ViewerViewModelTests`

Expected: all `ViewerViewModelTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ImageViewApp/Viewer/ViewerViewModel.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift
git commit -m "feat: recover from external image changes"
```

### Task 2: Trigger checks from window activity and navigation

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes `ViewerViewModel.refreshCurrentFileIfNeeded()`.

- [ ] **Step 1: Write a focused controller policy test**

```swift
func testExternalRefreshRunsForWindowActivationAndBeforeNavigation() {
    XCTAssertTrue(MainWindowController.shouldRefreshCurrentFile(for: .windowActivated))
    XCTAssertTrue(MainWindowController.shouldRefreshCurrentFile(for: .navigation))
}
```

- [ ] **Step 2: Run the focused test to verify failure**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter MainWindowControllerTests`

Expected: the test fails because the policy API does not exist.

- [ ] **Step 3: Implement the controller calls**

```swift
func windowDidBecomeKey(_ notification: Notification) {
    Task { await viewModel.refreshCurrentFileIfNeeded() }
}
```

Call the same helper before previous, next, and filmstrip selection actions.

- [ ] **Step 4: Run the full suite and build**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox`

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh`

Expected: all tests pass and `.build/ImageView.app` is produced.

- [ ] **Step 5: Commit**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift
git commit -m "feat: refresh external changes on window activity"
```
