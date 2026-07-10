# Progressive Image Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a bounded preview before the full-resolution image without blocking UI interaction.

**Architecture:** `ViewerViewModel` has separate asynchronous preview and full-image loaders. Only the full loader accesses `ImageCache`; both default loaders run decoding in detached tasks. Generation checks make result publication latest-request-wins.

**Tech Stack:** Swift concurrency, AppKit, ImageIO, XCTest, SwiftPM.

## Global Constraints

- Preview images never enter the full-image cache or persistent edit source.
- All decoding remains off the main actor.
- Existing navigation, editing, metadata and preload behavior remains full-resolution only.

---

### Task 1: Add preview-first view-model tests

**Files:**
- Modify: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`

- [ ] **Step 1: Write failing asynchronous tests**

```swift
func testOpenDisplaysPreviewBeforeFullImageAndPublishesFullMetadata() async throws {
    // Pause the controlled full loader, release preview first, and assert currentImage is preview while metadata is nil.
}

func testNewOpenIgnoresLatePreviewAndFullImageFromEarlierRequest() async throws {
    // Pause both results for the first URL, open the second URL, then release the first and assert the second remains visible.
}
```

- [ ] **Step 2: Run the focused test to verify failure**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ViewerViewModelTests`

Expected: compilation fails because no preview loader exists.

- [ ] **Step 3: Add separate preview and full loaders**

```swift
private let loadPreviewAtURL: @Sendable (URL, SupportedImageFormat) async throws -> DecodedImage

async let preview = loadPreviewAtURL(url, format)
async let full = loadImageAtURL(url, format)
if let previewImage = try? await preview, generation == openGeneration { currentImage = previewImage }
let image = try await full
```

Default closures decode in `Task.detached`; the preview closure requests `maxPixelSize: 2_048` and does not write the cache.

- [ ] **Step 4: Re-run focused tests and commit**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ViewerViewModelTests`

Expected: `ViewerViewModelTests` pass.

### Task 2: Complete regression verification

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Modify: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Ensure navigation still uses only full-resolution loading**

Keep `displayCurrentAndPreload()` on the full loader and update `persistedCurrentImage` only when a full result succeeds.

- [ ] **Step 2: Run complete verification**

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox`

Run: `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh`

Expected: all tests pass and `.build/ImageView.app` is produced.
