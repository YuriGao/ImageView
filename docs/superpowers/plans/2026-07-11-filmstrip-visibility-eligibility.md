# Filmstrip Visibility Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the filmstrip whenever no image is loaded or the canvas is zoomed above fit scale.

**Architecture:** Extend the existing pure filmstrip display predicate in `MainWindowController` so every reveal attempt uses the same eligibility rules. Existing current-image and canvas-transform callbacks immediately hide the overlay when eligibility is lost, while returning to fit scale waits for later pointer movement before revealing.

**Tech Stack:** Swift 6, AppKit, Combine, XCTest, Swift Package Manager

## Global Constraints

- Filmstrip display requires the setting enabled, a loaded image, canvas scale at or below `1.01`, and pointer activity.
- No loaded image hides the filmstrip immediately.
- Canvas scale above `1.01` hides the filmstrip immediately.
- Returning to scale `1.01` or below does not reveal automatically.
- Existing delayed auto-hide and hover suppression remain unchanged while eligible.

---

### Task 1: Enforce Filmstrip Display Eligibility

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes: `settings.showsFilmstrip`, `viewModel.currentImage`, `canvas.scale`, and pointer activity.
- Produces: `shouldDisplayFilmstripOverlay(isEnabled:hasLoadedImage:canvasScale:pointerIsActive:)`.

- [ ] **Step 1: Replace the existing eligibility test with failing coverage**

```swift
func testFilmstripRequiresEnabledLoadedFitScaleAndPointerActivity() {
    XCTAssertTrue(MainWindowController.shouldDisplayFilmstripOverlay(
        isEnabled: true,
        hasLoadedImage: true,
        canvasScale: 1.01,
        pointerIsActive: true
    ))
    XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
        isEnabled: true,
        hasLoadedImage: false,
        canvasScale: 1,
        pointerIsActive: true
    ))
    XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
        isEnabled: true,
        hasLoadedImage: true,
        canvasScale: 1.011,
        pointerIsActive: true
    ))
    XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
        isEnabled: false,
        hasLoadedImage: true,
        canvasScale: 1,
        pointerIsActive: true
    ))
    XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
        isEnabled: true,
        hasLoadedImage: true,
        canvasScale: 1,
        pointerIsActive: false
    ))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MainWindowControllerTests/testFilmstripRequiresEnabledLoadedFitScaleAndPointerActivity --disable-sandbox`

Expected: compilation fails because the expanded predicate signature does not exist.

- [ ] **Step 3: Implement the expanded predicate**

```swift
static func shouldDisplayFilmstripOverlay(
    isEnabled: Bool,
    hasLoadedImage: Bool,
    canvasScale: CGFloat,
    pointerIsActive: Bool
) -> Bool {
    isEnabled && hasLoadedImage && canvasScale <= 1.01 && pointerIsActive
}
```

- [ ] **Step 4: Use the predicate for reveal and transition hiding**

```swift
private func filmstripIsEligible(pointerIsActive: Bool) -> Bool {
    Self.shouldDisplayFilmstripOverlay(
        isEnabled: settings.showsFilmstrip,
        hasLoadedImage: viewModel.currentImage != nil,
        canvasScale: canvas.scale,
        pointerIsActive: pointerIsActive
    )
}
```

In `revealFilmstripOverlay()`, guard with `filmstripIsEligible(pointerIsActive: true)`. In the current-image sink, call `hideFilmstripOverlay(immediately: true)` when the new image is `nil`. In `canvas.onTransformChanged`, update zoom status and immediately hide the filmstrip when `scale > 1.01`; do not reveal when scale returns to `1.01` or below.

- [ ] **Step 5: Run focused and complete tests**

Run: `swift test --filter MainWindowControllerTests --disable-sandbox`

Expected: all controller tests pass with zero failures.

Run: `swift test --disable-sandbox`

Expected: all project tests pass with zero failures.

- [ ] **Step 6: Build and commit**

Run: `scripts/build-app.sh`

Expected: `.build/ImageView.app` is produced successfully.

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift docs/superpowers/plans/2026-07-11-filmstrip-visibility-eligibility.md
git commit -m "fix: constrain filmstrip visibility"
```
