# Task 5 Report: App Window, View Model, and First Image Open

## Implementation

- Replaced the temporary single-window bootstrap in `Sources/ImageViewApp/AppDelegate.swift` with a `MainWindowController`-driven launch flow.
- Added `Sources/ImageViewApp/MainWindowController.swift` to own the main `NSWindow`, bind the canvas and error overlay, and forward open requests to the view model.
- Added `Sources/ImageViewApp/Viewer/ViewerViewModel.swift` as the app-facing state object for:
  - opening an image URL,
  - decoding the first image with `ImageDecodeService.decode(url:format:maxPixelSize:)`,
  - initializing fallback navigation immediately,
  - scanning the containing directory,
  - replacing navigation with the scanned image sequence,
  - preloading nearby images into `ImageCache`,
  - exposing `currentImage` and localized error state.
- Added `Sources/ImageViewApp/Viewer/ImageCanvasView.swift` to render the current `DecodedImage` against a black background with fit-to-window scaling plus extra `scale`/`offset` state.
- Added `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift` to display centered error text over the canvas.
- Added an app test target in `Package.swift` and `Tests/ImageViewAppTests/ViewerViewModelTests.swift` so the task could be implemented test-first.

## TDD Notes

- Red: `swift test --disable-sandbox --filter ViewerViewModelTests` failed because `ViewerViewModel` did not exist yet.
- Green: after implementing the task files, the same filtered test run passed.

## Verification Commands and Output

### Filtered TDD test

Command:

```sh
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift test --disable-sandbox --filter ViewerViewModelTests
```

Result:

- PASS
- 2 tests executed, 0 failures

### Full build

Command:

```sh
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift build --disable-sandbox
```

Result:

- PASS
- `Build complete!`

## Third Review Fix Addendum

- Added `@Published private(set) var displayTitle` to `ViewerViewModel` and refreshed it whenever navigation changes or an open fails, so the title tracks the actual current item state instead of piggybacking on `$currentImage`.
- Switched `MainWindowController` to bind the window title from `$displayTitle`, leaving the image subscription responsible only for canvas rendering.
- Restricted detached neighbor preloading to background-safe formats with `ViewerViewModel.canPreloadInBackground(_:)`, which skips `.svg`, `.webp`, and `.avif` so AppKit-backed fallback decode paths are not invoked off-main.
- Expanded `ViewerViewModelTests` with regressions for title updates across navigation/failure and for the preload eligibility guard.

### Third Review Verification

Command:

```sh
HOME=$(pwd)/.build/home \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
SWIFTPM_PACKAGECACHE_PATH=$(pwd)/.build/package-cache \
swift test --disable-sandbox
```

Result:

- PASS
- 20 tests executed, 0 failures

Command:

```sh
HOME=$(pwd)/.build/home \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
SWIFTPM_PACKAGECACHE_PATH=$(pwd)/.build/package-cache \
swift build --disable-sandbox
```

Result:

- PASS
- `Build complete!`

### Third Review Notes

- SwiftPM still emitted readonly user-cache warnings in this harness even with workspace-local cache overrides, but both required commands completed successfully.

### Full test suite

Command:

```sh
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift test --disable-sandbox
```

Result:

- PASS
- 15 tests executed, 0 failures

### App launch check

Command:

```sh
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/ModuleCache \
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/ModuleCache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift run --disable-sandbox ImageView
```

Observed result:

- Build succeeded and the app entered its event loop until interrupted manually.
- In this environment, launch emitted LaunchServices/XPC warnings:
  - `Failure on line 688 in function id scheduleApplicationNotification...`
  - `Connection Invalid error for service com.apple.hiservices-xpcservice.`
- Because the process stayed running, startup appears successful, but I could not directly visually confirm the window contents from the shell-only run.

## Files Changed

- `Package.swift`
- `Sources/ImageViewApp/AppDelegate.swift`
- `Sources/ImageViewApp/MainWindowController.swift`
- `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`
- `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift`
- `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

## Self-Review

- The implementation follows the task brief closely and uses the Task 4 decode API `decode(url:format:maxPixelSize:)`.
- The new tests cover the primary behavior that matters for this task: first image open, initial decode, navigation state population from directory scan, and error handling for broken input.
- `@MainActor` was added to `AppDelegate` to keep AppKit calls actor-correct and avoid compiler diagnostics.
- I kept the app-surface changes scoped to `Sources/ImageViewApp` except for the minimal `Package.swift` and app test target additions needed for TDD.

## Concerns

- The task brief’s `application(_:open:)` logic calls `showWindowIfNeeded()` before checking whether `mainWindowController` is nil, which makes the `pendingOpenURLs` append branch effectively unreachable in the implemented flow. I preserved the requested structure instead of refactoring behavior beyond the brief.
- The shell environment could not provide direct visual confirmation of the black window, only successful build/startup evidence plus a still-running app process before manual interruption.
- SwiftPM still printed read-only user cache warnings even with workspace-local cache overrides, but build and test commands completed successfully with `--disable-sandbox`.

## Review Fix Addendum

- Cleared stale viewer state on open failure by only committing navigation after a successful decode and by resetting `currentImage` plus `navigationState` when the current open request fails.
- Simplified `AppDelegate.application(_:open:)` to a single-current-image policy: buffer one URL only before `applicationDidFinishLaunching(_:)`, then consistently open the last requested URL once the app is ready.
- Added open request generation tracking in `ViewerViewModel` so an older open that finishes later cannot overwrite the latest requested image/navigation state.
- Expanded `ViewerViewModelTests` with focused regressions for stale state after a failed open and for out-of-order open completion.

### Review Fix Verification

Command:

```sh
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/swiftpm-module-cache \
swift test --disable-sandbox
```

Result:

- PASS
- 17 tests executed, 0 failures

Command:

```sh
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/swiftpm-module-cache \
swift build --disable-sandbox
```

Result:

- PASS
- `Build complete!`

## Second Review Fix Addendum

- Refactored `ViewerViewModel` image loading so `display(url:format:)` returns a `DecodedImage` instead of publishing it directly. `open(url:)` now checks the open generation before assigning `currentImage` or fallback navigation, which closes the repeated-open race where an older decode could still overwrite the latest request.
- Changed the open flow to commit a single-image fallback navigation state immediately after a successful decode and to treat directory scan failure as non-fatal. When scan fails after decode succeeds, the opened image remains visible, navigation stays on the single opened item, and no generic open error is shown.
- Added two regressions in `ViewerViewModelTests`:
  - decode succeeds + scan fails preserves `currentImage` and one-item navigation
  - slow first decode + faster second open keeps the second image/navigation as the final state

### Second Review Verification

Command:

```sh
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/swiftpm-module-cache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift test --disable-sandbox
```

Result:

- PASS
- 18 tests executed, 0 failures

Command:

```sh
CLANG_MODULE_CACHE_PATH=$(pwd)/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$(pwd)/.build/swiftpm-module-cache \
SWIFTPM_CUSTOM_CACHE_PATH=$(pwd)/.build/swiftpm-cache \
SWIFTPM_SECURITY_DIRECTORY=$(pwd)/.build/swiftpm-security \
swift build --disable-sandbox
```

Result:

- PASS
- `Build complete!`
