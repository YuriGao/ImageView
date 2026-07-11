# Task 3 Report: File-Association Settings UI

## Status

Implemented the native AppKit file-association section and English/Simplified Chinese localization. No manual smoke test was run because it could mutate real system default file associations; all service-touching automated tests use fakes.

## RED / GREEN

- RED: Added representative `AppStringsTests` assertions and `PreferencesWindowControllerTests`. The focused command failed at compile time because `PreferencesWindowController` did not yet expose the required injected initializer (`extra arguments at positions #2, #3, #4`).
- First GREEN attempt exposed an AppKit API mismatch (`representedObject` belongs to `NSButtonCell`) and then a genuine constraint-order exception (row and stack lacked a common ancestor).
- GREEN: Stored format raw values on the button cell, activated row-width constraints after insertion, and reran the requested focused set: 17 tests passed, 0 failures.

## Verification

- Focused: `swift test --disable-sandbox --filter 'AppStringsTests|PreferencesWindowControllerTests|FileAssociationSettingsModelTests|DefaultApplicationServiceTests'` — 17 passed, 0 failed.
- Full: `swift test --disable-sandbox` — 145 passed, 0 failed.
- Release: `scripts/build-app.sh` — succeeded; produced `.build/ImageView.app`.
- Bundle check: `CFBundleDocumentTypes` still declares all ten image UTIs with role `Viewer` and rank `Alternate`.
- `git diff --check` — clean.
- Existing SwiftPM cache/resource warnings remain unchanged and are outside Task 3 scope.

## Self-review

- The model remains the sole source of selection/status/apply state; the controller only renders and routes AppKit target/actions.
- Rows rebuild only when `visibleFormats` changes; ordinary renders update existing controls.
- Apply/mutation controls disable while applying; apply title and summaries are localized.
- Row failures use system red; normal status uses the secondary label color; unsupported-type text is localized.
- `showWindow` refreshes statuses; production injects one owned workspace service through `AppDelegate`.
- No File-menu item, persisted selection, legacy Launch Services setter, external utility, or real association mutation was added.

## Files

- `Sources/ImageViewApp/Settings/PreferencesWindowController.swift`
- `Sources/ImageViewApp/AppDelegate.swift`
- `Sources/ImageViewApp/Localization/AppStrings.swift`
- `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- `Tests/ImageViewAppTests/PreferencesWindowControllerTests.swift`
- `Tests/ImageViewAppTests/AppStringsTests.swift`

## Commit

- Message: `feat: add image file association settings`
- SHA: the commit containing this report (reported to the parent task after creation).
