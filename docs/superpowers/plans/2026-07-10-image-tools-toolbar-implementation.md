# Image Tools Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact top image-tools toolbar that reuses existing navigation, editing, crop, mirror, and trash commands.

**Architecture:** `ImageToolsToolbarView` is a pure SwiftUI presentation component driven by `ImageToolsToolbarState`. `MainWindowController` owns actions, derives toolbar state from navigation/image/crop data, and makes toolbar visibility follow the established HUD lifecycle.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, XCTest, SwiftPM.

## Global Constraints

- Target macOS 14+ through the existing SwiftPM package.
- Keep work on `codex/v1-settings-filmstrip`; do not merge to `main` without explicit approval.
- Use SF Symbols image-only buttons with tooltip and accessibility label.
- Toolbar contains no direct file or image-editing logic.
- Hide toolbar during crop mode and whenever the HUD is hidden.

---

### Task 1: Pure Toolbar State and SwiftUI View

**Files:** Create `Sources/ImageViewApp/Viewer/ImageToolsToolbarView.swift`; create `Tests/ImageViewAppTests/ImageToolsToolbarViewTests.swift`.

**Interfaces:** Add `struct ImageToolsToolbarState: Equatable` with `canShowPrevious`, `canShowNext`, `canEdit`, `canMoveToTrash`, and `isVisible`; add `static func state(hasImage: Bool, position: Int?, itemCount: Int, isCropping: Bool) -> ImageToolsToolbarState`; add `struct ImageToolsToolbarView: View` with action closures.

- [ ] Write failing tests: a 3-item directory at position 0 enables only next; position 2 enables only previous; no image disables every action; crop mode makes `isVisible` false.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ImageToolsToolbarViewTests`; expect missing toolbar type failures.
- [ ] Implement state derivation and a material-backed SwiftUI `HStack` containing six fixed-size `Button`s. Use `chevron.left`, `chevron.right`, `rotate.right`, `crop`, `rectangle.lefthalf.inset.filled`, and `trash`; provide matching `.help` and `.accessibilityLabel` values; disable each button from the state.
- [ ] Re-run the focused test; expect pass. Commit with `git add Sources/ImageViewApp/Viewer/ImageToolsToolbarView.swift Tests/ImageViewAppTests/ImageToolsToolbarViewTests.swift` and `git commit -m "feat: add image tools toolbar view"`.

### Task 2: Controller Integration and Visibility

**Files:** Modify `Sources/ImageViewApp/MainWindowController.swift`; modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`.

**Interfaces:** Add `private let toolsToolbarView: NSHostingView<ImageToolsToolbarView>`; add `private func updateToolsToolbar()`; add `static func shouldShowToolsToolbar(isHUDVisible: Bool, isCropping: Bool) -> Bool`.

- [ ] Write failing tests asserting toolbar visibility requires visible HUD and inactive crop mode.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter MainWindowControllerTests`; expect missing visibility helper failure.
- [ ] Add the hosting view below HUD, constrained at 58 pt from the top and centered. Render state from `navigationState`, `currentImage`, and `cropOverlay.isCropping`; route closures to `navigateToPreviousImage()`, `navigateToNextImage()`, `rotateClockwise(nil)`, `startCropping(nil)`, `mirrorHorizontal(nil)`, and `moveCurrentImageToTrash(nil)`. Call `updateToolsToolbar()` from navigation/image/error/HUD refresh paths, crop start/cancel, and settings changes. Show/hide it alongside the HUD and re-evaluate in the HUD fade completion.
- [ ] Run full test suite and `scripts/build-app.sh`; expect all tests pass and ImageView.app builds. Commit with `git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift` and `git commit -m "feat: show image tools toolbar"`.
