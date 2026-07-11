# Unified Overlay Auto-Hide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the filmstrip and floating page controls use the same 1.8-second auto-hide delay and 0.18-second fade-out duration.

**Architecture:** Keep both overlay visibility state machines independent, but replace their duplicated timing constants with shared constants owned by `MainWindowController`. Both timer schedulers and both animated hide paths consume the same values.

**Tech Stack:** Swift 6, AppKit, XCTest, Swift Package Manager

## Global Constraints

- Both overlays wait exactly 1.8 seconds before fading.
- Both overlays fade out over exactly 0.18 seconds.
- Hover cancellation, timer generation tokens, and eligibility rules remain independent and unchanged.
- Reveal animation durations remain unchanged.
- Do not merge timers or add a configurable timeout.

---

### Task 1: Share Overlay Disappearance Timing

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Produces: `MainWindowController.overlayAutoHideDelay: TimeInterval`
- Produces: `MainWindowController.overlayFadeOutDuration: TimeInterval`
- Removes: `filmstripAutoHideDelay` and `pageControlsAutoHideDelay`

- [ ] **Step 1: Write the failing timing test**

Add this focused test:

```swift
func testFilmstripAndPageControlsShareDisappearanceTiming() {
    XCTAssertEqual(MainWindowController.overlayAutoHideDelay, 1.8)
    XCTAssertEqual(MainWindowController.overlayFadeOutDuration, 0.18)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MainWindowControllerTests/testFilmstripAndPageControlsShareDisappearanceTiming --disable-sandbox`

Expected: compilation fails because `overlayAutoHideDelay` and `overlayFadeOutDuration` do not exist.

- [ ] **Step 3: Add shared constants and update both paths**

Replace the two delay constants with:

```swift
static let overlayAutoHideDelay: TimeInterval = 1.8
static let overlayFadeOutDuration: TimeInterval = 0.18
```

Use `overlayAutoHideDelay` in both `scheduleFilmstripAutoHide()` and `schedulePageControlsAutoHide()`. Use `overlayFadeOutDuration` in the non-immediate branches of both `hideFilmstripOverlay(immediately:)` and `hidePageControls(immediately:)`. Leave both reveal animation durations unchanged.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `swift test --filter MainWindowControllerTests --disable-sandbox`

Expected: all `MainWindowControllerTests` pass with zero failures.

- [ ] **Step 5: Run complete verification**

Run: `swift test --disable-sandbox`

Expected: the complete project test suite passes with zero failures.

Run: `scripts/build-app.sh`

Expected: the Release app bundle is produced successfully.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 6: Commit the fix**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift docs/superpowers/plans/2026-07-11-unified-overlay-auto-hide.md
git commit -m "fix: unify overlay auto-hide timing"
```
