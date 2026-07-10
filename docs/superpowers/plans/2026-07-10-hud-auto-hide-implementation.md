# HUD Auto-Hide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the unpinned ImageView HUD appear for user activity and fade after 1.8 seconds, while keeping pinned HUD visible.

**Architecture:** `MainWindowController` owns visibility state, a cancellable `DispatchWorkItem`, and the root-view tracking area. Static helpers model visibility decisions for unit tests. `HUDView` remains a pure presentation view.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Combine, XCTest, SwiftPM.

## Global Constraints

- Target macOS 14+ through the existing SwiftPM package.
- Keep work on `codex/v1-settings-filmstrip`; do not merge to `main` without explicit approval.
- Unpinned HUD timeout is exactly 1.8 seconds.
- Pinned HUD must remain visible and must not retain an auto-hide task.
- HUD content must update before each visibility change.

---

### Task 1: HUD Visibility State and Policy Tests

**Files:** Modify `Sources/ImageViewApp/MainWindowController.swift`; modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`.

**Interfaces:** Add `enum HUDVisibilityAction { case showIndefinitely, showTemporarily, hide }`; add `static func hudVisibilityAction(isPinned: Bool, isActivity: Bool) -> HUDVisibilityAction`; add `static func shouldScheduleHUDHide(isPinned: Bool) -> Bool`.

- [ ] Write failing tests asserting pinned HUD returns `.showIndefinitely` and does not schedule hiding; unpinned activity returns `.showTemporarily` and schedules hiding; unpinned nonactivity returns `.hide`.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter MainWindowControllerTests`; expect missing HUD policy API failures.
- [ ] Implement the static policy helpers and controller fields `hudHideWorkItem` plus `hudTrackingArea`. Add `showHUDTemporarily()` to update content, unhide, cancel a prior work item, and schedule a new main-queue work item at `.now() + 1.8`. Add `hideHUDIfUnpinned()` to hide only when `settings.pinsHUD` is false. Add `showPinnedHUD()` to cancel pending hide and unhide.
- [ ] Re-run focused controller tests; expect pass. Commit with `git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift` and `git commit -m "feat: add HUD auto-hide state"`.

### Task 2: Window Activity and Settings Integration

**Files:** Modify `Sources/ImageViewApp/MainWindowController.swift`; modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`.

**Interfaces:** Override `updateTrackingAreas()` and `mouseMoved(with:)`; add `func refreshHUDForActivity()`.

- [ ] Write failing tests that policy helpers leave `pinsHUD` unchanged and that settings transitions map to persistent visibility for pinned versus timed visibility for unpinned state.
- [ ] Run the focused controller test command; expect missing or incorrect settings-policy behavior.
- [ ] Add an `.activeInKeyWindow` root-view tracking area for `.mouseMoved`; route mouse movement, transform updates, navigation changes, error-message updates, and `applySettings()` through `refreshHUDForActivity()`. Fixed HUD uses `showPinnedHUD()`; unpinned HUD calls `showHUDTemporarily()`. Remove tracking area and cancel the work item in `deinit`.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox`; expect all tests pass. Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh`; expect ImageView.app builds successfully. Commit with `git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift` and `git commit -m "feat: auto-hide unpinned HUD"`.
