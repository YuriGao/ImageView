# Save As Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow edited images to be written to a user-selected new file and format without changing the original.

**Architecture:** Core defines writable target formats and performs safe target writes. View model commits a successful alternate destination into navigation and cache. Controller owns NSSavePanel and menu routing.

**Tech Stack:** Swift 6, AppKit, ImageIO, UniformTypeIdentifiers, XCTest, SwiftPM.

## Global Constraints

- Target macOS 14+ through existing SwiftPM package.
- Keep work on `codex/v1-settings-filmstrip`; do not merge to main without explicit approval.
- Original URL is never overwritten by Save As.
- Save As supports PNG, JPEG, TIFF, BMP, and conditionally HEIC/HEIF.
- Cancel and failure keep unsaved edit state.

---

### Task 1: Target Write API

**Files:** Modify `Sources/ImageViewCore/Editing/ImageEditingService.swift`; modify `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`.

- [ ] Add failing tests for supported target formats and a PNG write to a new temporary URL that preserves source URL contents.
- [ ] Run `swift test --disable-sandbox --filter ImageEditingServiceTests`; expect missing target-format API failure.
- [ ] Add `public static func writableSaveFormats() -> [SupportedImageFormat]` and reuse `save(_:to:format:)` for a target URL while retaining temporary-file atomic writes. Include only formats that have a usable UTI/writer.
- [ ] Re-run focused tests and commit with `git commit -m "feat: support alternate edit destinations"`.

### Task 2: View Model Commit

**Files:** Modify `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`; modify `Tests/ImageViewAppTests/ViewerViewModelTests.swift`.

- [ ] Add failing test for successful alternate save: pending edits clear, current item URL becomes target, image dimensions remain edited, and navigation includes target.
- [ ] Run `swift test --disable-sandbox --filter ViewerViewModelTests`; expect missing API failure.
- [ ] Add `saveCurrentEdits(to:format:) -> Bool`; write current CGImage, replace current item URL/format, update cache and metadata, clear pending edits, and update title. On failure retain current item and unsaved edits.
- [ ] Re-run focused tests and commit with `git commit -m "feat: commit saved edit destination"`.

### Task 3: Save Panel and Menu

**Files:** Modify `Sources/ImageViewApp/MainWindowController.swift`; modify `Sources/ImageViewApp/AppDelegate.swift`; modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`.

- [ ] Add failing selector and menu-validation tests for `saveEditsAs(_:)` requiring an image with unsaved edits.
- [ ] Run `swift test --disable-sandbox --filter MainWindowControllerTests`; expect missing command failure.
- [ ] Add Edit > Save As… with Cmd+Shift+S. Configure NSSavePanel allowed content types from writable formats, default name `original-edited`, then call view-model target save only on confirmation. Cancel changes nothing; write failure retains existing error state.
- [ ] Run full `swift test --disable-sandbox` and `scripts/build-app.sh`, then commit with `git commit -m "feat: save edited images as new files"`.
