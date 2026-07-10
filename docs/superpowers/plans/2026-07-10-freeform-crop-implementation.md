# Freeform Crop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add freeform crop mode that turns a draggable rectangle into the existing `EditOperation.crop` image edit.

**Architecture:** `ImageCanvasView` exposes display geometry and converts it to pixels. `CropOverlayView` owns crop-box manipulation. `MainWindowController` owns mode and command routing; it applies the existing `ViewerViewModel.applyEdit(.crop(_:))` path.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, SwiftPM, XCTest.

## Global Constraints

- Target macOS 14+ using the existing SwiftPM package.
- Keep changes on `codex/v1-settings-filmstrip`; no merge to `main` without explicit approval.
- Preserve touchpad browsing outside crop mode.
- A crop must be nonempty and within the source pixels.
- An unconfirmed crop box must not create unsaved edits.

---

### Task 1: Canvas Geometry

**Files:** Modify `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`; modify `Tests/ImageViewAppTests/ImageCanvasViewTests.swift`.

**Interfaces:** Add `var imageDrawRect: CGRect?` and `func pixelCropRect(for canvasRect: CGRect) -> CGRect?`.

- [ ] Write failing tests for a 200 x 100 image in a 400 x 300 canvas: a displayed crop rect `(120, 110, 160, 80)` returns pixel rect `(20, 30, 160, 80)`, and an outside rectangle is clipped to the source boundaries.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter ImageCanvasViewTests`; expect compilation failure because the geometry APIs do not exist.
- [ ] Implement `imageDrawRect` with the same fit scale, `scale`, and `offset` used in `draw(_:)`. Implement `pixelCropRect(for:)` by intersecting canvas rect with the draw rect, scaling to source pixels, integralizing, and intersecting with `CGRect(x: 0, y: 0, width: image.cgImage.width, height: image.cgImage.height)`.
- [ ] Re-run the focused test; expect pass. Commit with `git add Sources/ImageViewApp/Viewer/ImageCanvasView.swift Tests/ImageViewAppTests/ImageCanvasViewTests.swift` and `git commit -m "feat: add crop canvas geometry"`.

### Task 2: Crop Overlay

**Files:** Modify `Sources/ImageViewApp/Viewer/CropOverlayView.swift`; create `Tests/ImageViewAppTests/CropOverlayViewTests.swift`.

**Interfaces:** Add `enum CropHandle`; add `func beginCropping(in: CGRect)`, `func endCropping()`, `func moveCrop(by: CGPoint)`, and `func resizeCrop(edge: CropHandle, by: CGPoint)`; expose `var isCropping: Bool`.

- [ ] Write failing tests: entering crop on `(50, 100, 300, 200)` creates `(80, 120, 240, 160)`; translating an existing crop by a large positive delta leaves max X/Y equal to image bounds; resizing cannot produce a side under 24 points.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter CropOverlayViewTests`; expect missing API failures.
- [ ] Persist `imageRect`, initialize with a 10% inset, enforce a 24-point minimum side, and constrain all mutations to `imageRect`. Draw an even-odd dimmed exterior mask, accent border, and eight 8-point handles. Use 10-point hit testing to select a corner, edge, or interior move operation; wire AppKit mouse down/drag/up to those methods.
- [ ] Re-run focused tests; expect pass. Commit with `git add Sources/ImageViewApp/Viewer/CropOverlayView.swift Tests/ImageViewAppTests/CropOverlayViewTests.swift` and `git commit -m "feat: add interactive crop overlay"`.

### Task 3: Crop Mode Commands

**Files:** Modify `Sources/ImageViewApp/MainWindowController.swift`; modify `Sources/ImageViewApp/AppDelegate.swift`; modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`.

**Interfaces:** Add `startCropping(_:)`, `applyCrop(_:)`, and `cancelCrop(_:)`. Extend `KeyAction` with `startCropping`, `applyCrop`, and `cancelCrop`. Extend `MenuCommand` with `startCropping`.

- [ ] Write failing tests asserting Cmd+K key code 40 starts crop, Enter applies and Esc cancels while crop mode is active, and the Crop menu command requires a current image.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter MainWindowControllerTests`; expect missing crop command failures.
- [ ] Add `CropOverlayView` above the canvas, constrained to canvas edges. Add Edit > Crop with Cmd+K and target wiring. Starting calls `beginCropping(in: canvas.imageDrawRect)` and disables canvas interaction. Applying converts `cropOverlay.cropRect` with `canvas.pixelCropRect(for:)`, calls `performEdit(.crop(pixelRect))`, and exits mode. Cancel only exits mode. While cropping, Enter/Esc take priority; opening, navigating, selecting, renaming, trashing, and closing call cancel first.
- [ ] Re-run focused tests; expect pass. Commit with `git add Sources/ImageViewApp/MainWindowController.swift Sources/ImageViewApp/AppDelegate.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift` and `git commit -m "feat: add crop mode controls"`.

### Task 4: Regression Tests and Verification

**Files:** Modify `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`; modify `Tests/ImageViewAppTests/ViewerViewModelTests.swift`.

- [ ] Add a core test that crops a 5 x 4 source at `(1, 1, 3, 2)` and asserts a 3 x 2 output.
- [ ] Add a view-model test that opens a 5 x 3 fixture, applies `.crop(CGRect(x: 1, y: 1, width: 3, height: 2))`, asserts 3 x 2 and unsaved edits, discards, then asserts restoration to 5 x 3.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox`; expect all tests pass.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh`; expect successful ImageView.app bundle build.
- [ ] Commit the regression coverage with `git add Tests/ImageViewCoreTests/ImageEditingServiceTests.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift` and `git commit -m "test: cover freeform crop edits"`.
