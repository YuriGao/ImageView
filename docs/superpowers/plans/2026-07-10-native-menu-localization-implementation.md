# Native Menu and Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the floating HUD tools with a complete, localized native macOS menu bar.

**Architecture:** `AppDelegate` owns menu construction using a small localization helper. `MainWindowController` remains the action target and gains menu actions for navigation and canvas sizing. HUD-specific state, preferences, and views are removed while file dropping remains on the root view.

**Tech Stack:** Swift 6, AppKit, SwiftUI, XCTest, Swift Package Manager.

## Global Constraints

- Target macOS 14; keep existing keyboard equivalents.
- Localize English and Simplified Chinese using macOS preferred localization; use English fallback.
- Keep title bar, bottom status bar, crop controls, inspector, filmstrip, and file dropping.
- Remove HUD, floating tools, visibility timer, and Pin HUD setting.

---

### Task 1: Localize application strings

**Files:**
- Create: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Create: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Create: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Package.swift`, `scripts/build-app.sh`
- Test: `Tests/ImageViewAppTests/AppStringsTests.swift`

**Interfaces:** Produces `AppStrings.text(_:bundle:)`, backed by `Bundle.localizedString(forKey:value:table:)`.

- [ ] Write a failing test that resolves `menu.file` as `File` from English and `文件` from Simplified Chinese.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter AppStringsTests`; expect failure because `AppStrings` does not exist.
- [ ] Add `AppStrings`, process `Resources` in `Package.swift`, create both string tables, and copy `.lproj` folders during app packaging.
- [ ] Re-run the focused test; expect pass.
- [ ] Commit with `git add Package.swift scripts/build-app.sh Sources/ImageViewApp/Localization Sources/ImageViewApp/Resources Tests/ImageViewAppTests/AppStringsTests.swift && git commit -m "feat: add app menu localization"`.

### Task 2: Build the native menu hierarchy

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Test: `Tests/ImageViewAppTests/AppDelegateTests.swift`

**Interfaces:** Produces `func makeMainMenu() -> NSMenu`. Consumes menu action selectors on `MainWindowController` and `AppStrings.text(_:bundle:)`.

- [ ] Write a failing test that calls `makeMainMenu()` and asserts top-level menus `ImageView`, `File`, `View`, `Image`, `Window`, `Help`, including `Next Image`, `Rotate Clockwise`, and `Crop`.
- [ ] Run the focused `AppDelegateTests` filter; expect compilation failure because `makeMainMenu()` does not exist.
- [ ] Extract menu creation from `installMainMenuIfNeeded()` into `makeMainMenu()`. Add File entries Open (`Cmd-O`), Open Recent, Close (`Cmd-W`), Rename, Reveal, Copy Path, and Move to Trash. Add View entries Previous/Next, Actual Size, Zoom to Fit, Filmstrip, Info, Full Screen. Put rotate/flip/crop/save operations in Image. Add standard Window and Help menus. Use localization keys for all labels and preserve targets.
- [ ] Re-run `AppDelegateTests`; expect pass.
- [ ] Commit with `git add Sources/ImageViewApp/AppDelegate.swift Tests/ImageViewAppTests/AppDelegateTests.swift && git commit -m "feat: add complete native menu bar"`.

### Task 3: Route View commands through the controller

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:** Produces `showPreviousImage(_:)`, `showNextImage(_:)`, `actualSize(_:)`, and `zoomToFit(_:)` actions. Uses `ImageCanvasView` fit/actual-size APIs.

- [ ] Write a failing test that maps the four selectors through `menuCommand(for:)` and verifies navigation/sizing enablement when no decoded image exists.
- [ ] Run `swift test --disable-sandbox --filter MainWindowControllerTests/testMenuCommandMapsViewSelectors`; expect selector compilation failure.
- [ ] Add the four action methods, command enum cases, mapping, and validation. Navigation calls existing guarded next/previous methods; sizing is enabled only with an image.
- [ ] Re-run `MainWindowControllerTests`; expect pass.
- [ ] Commit with `git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift && git commit -m "feat: route view menu commands"`.

### Task 4: Remove HUD infrastructure without losing file drops

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`, `Sources/ImageViewApp/Settings/AppSettings.swift`, `Sources/ImageViewApp/Settings/PreferencesWindowController.swift`
- Delete: `Sources/ImageViewApp/Viewer/HUDView.swift`, `Sources/ImageViewApp/Viewer/ImageToolsToolbarView.swift`
- Modify: `Sources/ImageViewApp/Viewer/HUDTrackingView.swift`
- Delete: `Tests/ImageViewAppTests/HUDViewTests.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`, `Tests/ImageViewAppTests/AppSettingsTests.swift`

**Interfaces:** `HUDTrackingView` becomes a drop-only root view with `onFileDropped`; status updates are handled directly by the controller.

- [ ] Write a failing test for `MainWindowController.usesFloatingTools == false` and remove HUD visibility expectations from the existing test suite.
- [ ] Run the focused controller and settings tests; expect the new property assertion to fail.
- [ ] Remove HUD/tool hosted views, constraints, timer, mouse-move callback, visibility helpers, and `pinsHUD`. Keep `HUDTrackingView` only for file drops. Update crop callbacks to avoid removed toolbar refreshes; continue updating the bottom status label when image or zoom changes.
- [ ] Re-run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'MainWindowControllerTests|AppSettingsTests'`; expect pass.
- [ ] Commit with `git add Sources/ImageViewApp/MainWindowController.swift Sources/ImageViewApp/Settings Sources/ImageViewApp/Viewer/HUDTrackingView.swift Tests/ImageViewAppTests && git rm Sources/ImageViewApp/Viewer/HUDView.swift Sources/ImageViewApp/Viewer/ImageToolsToolbarView.swift Tests/ImageViewAppTests/HUDViewTests.swift && git commit -m "refactor: remove floating image tools"`.

### Task 5: Localize remaining UI and package verification

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`, `Sources/ImageViewApp/Settings/PreferencesWindowController.swift`, `Sources/ImageViewApp/Viewer/CropControlsView.swift`
- Test: `Tests/ImageViewAppTests/AppStringsTests.swift`

**Interfaces:** `AppStrings.requiredKeys` defines all menu and app-owned label keys; alerts and controls call `AppStrings.text`.

- [ ] Write a failing test that every `requiredKeys` value resolves to non-key strings in both localizations.
- [ ] Run the focused test; expect failure because the complete key list is absent.
- [ ] Replace application-owned hard-coded labels in alerts, preferences, and crop controls with localized keys. Keep file paths, filenames, and user image metadata unchanged.
- [ ] Run `env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox && env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh`; expect all tests to pass and output `/Users/gaoyinrui/Documents/Codex/ImageView/.build/ImageView.app`.
- [ ] Commit with `git add Sources/ImageViewApp Tests/ImageViewAppTests scripts/build-app.sh Package.swift && git commit -m "feat: localize image viewer interface"`.
