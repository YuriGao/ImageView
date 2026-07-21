# Scroll Input Direction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `dispatching-parallel-agents` when tasks are genuinely independent; otherwise use `executing-plans`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Correction after device acceptance:** AppKit's delivered deltas must not be inverted a second time. For ImageView's semantic actions, positive vertical movement zooms out and positive horizontal movement navigates to the previous image, matching native content movement on the accepted device setup.

**Goal:** Make image navigation, modifier-wheel zoom, and zoomed content panning follow the macOS scrolling direction consistently.

**Architecture:** Use AppKit's delivered `scrollingDeltaX/Y` for navigation, zoom, and panning because those values already respect the user's scroll preference. Do not undo `isDirectionInvertedFromDevice`. Continue routing directional callbacks through `MainWindowController`, which already applies left-to-right or right-to-left reading direction.

**Tech Stack:** Swift 6, AppKit `NSEvent`, XCTest, Swift Package Manager, shell packaging scripts, GitHub pull request workflow.

## Global Constraints

- Do not modify continuous-reading `NSScrollView` behavior.
- Do not infer a definitive hardware type from `hasPreciseScrollingDeltas`; use it only to retain the existing continuous-horizontal-navigation eligibility rule.
- Preserve one navigation per gesture, threshold accumulation, phase reset, and momentum suppression.
- Keep existing user settings and file operations unchanged.
- Implement with red-green TDD and run the complete Swift test suite before installation or publication.

---

### Task 0: Stabilize the existing navigation-race fixture

**Files:**
- Modify: `Tests/ImageViewAppTests/ViewerViewModelTests.swift:414-453`

**Interfaces:**
- Consumes: `ViewerViewModel` neighbor preloading and `SequencedImageLoader` test plans.
- Produces: A deterministic existing regression test whose second image remains available whether or not neighbor preloading consumes the first planned result.

- [x] **Step 1: Preserve the observed RED baseline**

Run:

```bash
swift test --disable-sandbox --filter 'ViewerViewModelTests.testNavigationInvalidatesOlderOpenBeforeItsFullImageArrives'
```

Observed on untouched `upstream/main`: FAIL because the initial open may preload `secondURL`, consuming the fixture's only planned result before `showNext()` displays it.

- [x] **Step 2: Make the fixture safe for preload plus display**

Give `secondURL` two identical `SequencedImageLoader.Plan` values. The first may be consumed by neighbor preloading and the second remains for the visible navigation request; if preloading is cancelled first, the visible request consumes the first and the extra plan is harmless.

- [x] **Step 3: Verify the existing race test is GREEN repeatedly**

Run the focused test three times. Expected: three passes with zero failures.

---

### Task 1: Lock the system-adjusted direction contract with regression tests

**Files:**
- Modify: `Tests/ImageViewAppTests/ImageCanvasViewTests.swift:114-192`

**Interfaces:**
- Consumes: `ImageCanvasView.handleScroll(deltaX:deltaY:at:modifierFlags:phase:momentumPhase:hasPreciseScrollingDeltas:isDirectionInvertedFromDevice:)`
- Produces: Regression coverage proving that delivered delta signs control navigation, modifier zoom, and panning regardless of how those deltas relate to the physical device.

- [x] **Step 1: Add system-adjusted navigation tests**

Add tests proving that delivered `deltaX = 80` invokes `onPrevious` and delivered `deltaX = -80` invokes `onNext`, with both values of `isDirectionInvertedFromDevice`.

- [x] **Step 2: Add zoom and panning direction tests**

Add tests proving that positive delivered `deltaY` zooms out, negative delivered `deltaY` zooms in, and zoomed panning uses the same system-adjusted deltas without device-direction compensation.

- [x] **Step 3: Add coarse-wheel isolation coverage**

Call `handleScroll` with `hasPreciseScrollingDeltas = false` and confirm that no image-navigation callback fires.

- [x] **Step 4: Run the focused suite and verify RED**

Run:

```bash
swift test --disable-sandbox --filter ImageCanvasViewTests
```

Expected: the system-adjusted direction tests fail while the handler still undoes `isDirectionInvertedFromDevice`.

---

### Task 2: Use AppKit-adjusted direction at the input boundary

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ImageCanvasView.swift:232-340`
- Test: `Tests/ImageViewAppTests/ImageCanvasViewTests.swift`

**Interfaces:**
- Consumes: AppKit scrolling deltas and `NSEvent.isDirectionInvertedFromDevice` as regression-test context.
- Produces: `handleScroll(..., isDirectionInvertedFromDevice: Bool = false)` whose behavior follows the delivered deltas for navigation, zoom, and panning.

- [x] **Step 1: Extend the handler input**

Keep passing `event.isDirectionInvertedFromDevice` into the testable handler so regression tests can prove it does not cause a second inversion.

- [x] **Step 2: Remove device-direction normalization**

Inside `handleScroll`, use delivered `deltaX/Y` unchanged for every scroll-driven behavior. AppKit has already applied the user's scrolling preference.

- [x] **Step 3: Apply semantic mappings**

Use `1.0 - deltaY * 0.01` for modifier-wheel zoom. Accumulate `deltaX` for navigation and map positive delivered movement to `onPrevious`, negative delivered movement to `onNext`.

- [x] **Step 4: Run the focused suite and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter ImageCanvasViewTests
```

Expected: all focused tests pass with zero failures.

---

### Task 3: Validate, install, and publish

**Files:**
- Verify: `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`
- Verify: `Tests/ImageViewAppTests/ImageCanvasViewTests.swift`
- Verify: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`
- Verify: `docs/superpowers/plans/2026-07-16-scroll-input-direction-implementation.md`

**Interfaces:**
- Consumes: the completed branch and project build/install scripts.
- Produces: a verified `/Applications/ImageView.app`, a GitHub pull request targeting `YuriGao/ImageView:main`, and synchronized local and remote main branches.

- [x] **Step 1: Run full automated verification**

Run:

```bash
swift test --disable-sandbox
scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 .build/ImageView.app
git diff --check
```

Expected: all tests pass, Release build succeeds, code signing is valid, and diff check is clean.

- [x] **Step 2: Perform installed-app acceptance**

Use the installed development build to verify application launch and the system-file-picker-to-viewer flow. Exercise the system-adjusted direction contract with deterministic event inputs for both values of `isDirectionInvertedFromDevice`. Confirm final direction on a physical trackpad or mouse because UI automation cannot reproduce the user's device motion.

- [x] **Step 3: Install and verify the local application**

Run:

```bash
scripts/install-app.sh
```

Verify the running executable is `/Applications/ImageView.app/Contents/MacOS/ImageView`, its SHA-256 matches the installed bundle, and the bundle passes strict `codesign` verification.

- [ ] **Step 4: Commit and push the branch**

Stage only the touched code/test files and this plan, commit with `fix: normalize scroll input direction`, and push `codex/fix-scroll-input-direction`.

- [ ] **Step 5: Open and merge the pull request**

Create a ready pull request targeting `YuriGao/ImageView:main` with the root cause, behavior contract, and validation evidence. Merge only after required GitHub checks pass, then update the local `main` branch to the merged upstream commit and reinstall if the merge commit changes the source tree.
