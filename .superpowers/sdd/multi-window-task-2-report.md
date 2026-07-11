# Task 2 Report: AppDelegate Multi-Window Management

## Status

Implementation and verification complete. Git commit blocked because the sandbox exposes `.git` read-only and the required escalation was rejected by the approval layer due to the current usage limit.

## TDD Evidence

### RED

Added AppDelegate tests first, then ran:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter AppDelegateTests
```

The build failed as expected because the injected factory/show/open/terminate initializer parameters, `finishLaunchingForTesting`, URL pipeline, controller lifecycle methods, and test surfaces did not yet exist.

### GREEN

Implemented the minimum production behavior and reran the AppDelegate suite: 17 tests passed, 0 failures.

Covered:

- exactly one empty image controller at launch;
- first URL reuses the only unassigned controller and subsequent URLs create independent controllers;
- full prelaunch URL order, including duplicate URLs;
- removal of one controller without affecting others;
- final image controller requests termination exactly once;
- unknown/duplicate close callbacks are idempotent;
- Settings controller existence does not prevent final-image termination;
- active/key image controller menu routing;
- Settings focus preserves the most recently active image target;
- closing the final controller clears controller-action menu targets while retaining app-owned targets.

The test harness injects no-op image-window presentation and termination closures. `finishLaunchingForTesting` does not activate the app. The Settings test helper constructs but does not show its window.

## Verification

- Focused AppDelegate + MainWindowController tests: 44 passed, 0 failures.
- Full test suite: 172 passed, 0 failures.
- Release build: succeeded; artifact at `/Users/gaoyinrui/Documents/Codex/ImageView/.build/ImageView.app`.
- `git diff --check`: passed.
- Manual production-window smoke test: intentionally not run because the task explicitly prohibits displaying production windows during tests/verification.

SwiftPM emitted pre-existing sandbox/cache/resource warnings, and AppKit emitted environment service diagnostics; all commands exited 0 and all XCTest assertions passed.

## Self-Review

- Changes are limited to `Sources/ImageViewApp/AppDelegate.swift` and `Tests/ImageViewAppTests/AppDelegateTests.swift`, plus this requested report.
- URL dispatch uses synchronous `hasAssignedOpenRequest` assignment, ensuring only the first URL can reuse the startup controller.
- Pending launch URLs append the complete arrays and drain once in stable order.
- Menu recursion changes targets only for MainWindowController commands and the two toggle selectors, preserving Open, Settings, appearance, Help, and Quit ownership.
- Controller ownership and termination are based solely on live image controllers, not Settings windows.
- No known correctness concerns remain in the requested scope.

## Commit

SHA: **BLOCKED — no commit created**.

Attempted commit command:

```bash
git add Sources/ImageViewApp/AppDelegate.swift Tests/ImageViewAppTests/AppDelegateTests.swift
git commit -m "feat: support multiple image windows"
```

Initial attempt failed creating `.git/index.lock` because `.git` is read-only. The required escalated retry was rejected by the approval layer due to the current usage limit. The verified modifications remain unstaged in the shared working tree.

---

## Review Findings Follow-up (2026-07-11)

### Status

Both review findings are fixed and verified.

### TDD Evidence

RED:

- Extended `WindowHarness` to count presentations per controller and asserted the startup window is shown once, a reused empty window is shown once more, and each newly created URL window is shown exactly once.
- Added a regression test proving that constructing an offscreen menu after injecting the installed menu cannot redirect production menu routing.
- The focused test build failed before implementation because the explicit installed-menu test seam did not exist; the pre-fix implementation also presented newly created URL windows twice.

GREEN:

- `createImageWindow()` now only creates, configures, and registers a controller. Startup and URL-opening call sites own presentation, so every relevant path has one explicit presentation action.
- `connectMenuTargets()` now routes only through `installedMainMenu`. Production records that menu only after assigning it to `NSApp.mainMenu`; tests use `setInstalledMainMenuForTesting(_:)` without mutating global application menu state.
- Removed retained references to controller-action items from arbitrary constructed menus, preventing offscreen menu construction from affecting routing.

### Verification

- `swift test --filter AppDelegateTests`: 18 passed, 0 failures.
- `swift test`: 173 passed, 0 failures.
- `swift build -c release`: succeeded.
- `git diff --check`: passed.
- SwiftPM continues to report the pre-existing warning for three unhandled resource files; it does not fail the build.

### Focus Points

- Startup empty window presentation count: 1.
- Reused startup window presentation count after opening its first URL: 2 total.
- Every newly created URL window presentation count: 1 total.
- Menu routing is based on installation, not construction order; the test seam is explicit and isolated from `NSApp.mainMenu`.
