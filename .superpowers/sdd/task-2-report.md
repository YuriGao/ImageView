# Task 2 Report: Format Detection and Same-Folder Scanning

## Implementation

Added the Task 2 core model and directory scanning layer under `ImageViewCore`:

- `SupportedImageFormat` supports the required image extensions, exposes `canAttemptSafeWrite`, and maps each case to a `UTType`.
- `ImageItem` wraps a browsable image URL plus its detected format.
- `NaturalSort.compare` uses localized standard comparison for human-friendly ordering.
- `DirectoryScanner.scan(containing:)` scans only the opened file’s directory, filters to supported regular image files, and returns naturally sorted `ImageItem` values.

## Tests

Added the requested tests:

- `SupportedImageFormatTests`
- `NaturalSortTests`
- `DirectoryScannerTests`

## TDD Evidence

I wrote the tests first, then ran them before any production code:

- `swift test --filter SupportedImageFormatTests` initially failed with missing type errors for `SupportedImageFormat`.
- `swift test --filter NaturalSortTests` initially failed with missing type errors for `NaturalSort`.
- `swift test --filter DirectoryScannerTests` initially failed with a failing assertion because the scanner result did not preserve the opened file URL exactly.

After implementing the production files and adjusting the scanner to preserve the opened file URL when it is part of the directory listing, all targeted tests passed.

## Verification

Final verification run:

- `swift test`

Result:

- Passed: 5 tests, 0 failures

## Files Changed

Created:

- `Sources/ImageViewCore/Models/SupportedImageFormat.swift`
- `Sources/ImageViewCore/Models/ImageItem.swift`
- `Sources/ImageViewCore/Directory/NaturalSort.swift`
- `Sources/ImageViewCore/Directory/DirectoryScanner.swift`
- `Tests/ImageViewCoreTests/SupportedImageFormatTests.swift`
- `Tests/ImageViewCoreTests/NaturalSortTests.swift`
- `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`

## Self-Review

- The implementation matches the task scope and stays inside the requested model and directory folders.
- Sorting is stable and human-friendly via `localizedStandardCompare`.
- The scanner excludes unsupported formats and hidden files, and only returns regular files.
- `SupportedImageFormat`, `ImageItem`, and `DirectoryScanner` now align closely with the task brief’s signatures, including `Sendable` where feasible.

## Concerns

- `DirectoryScanner` uses `@unchecked Sendable` because `FileManager` is not `Sendable` in this SDK. That is acceptable for this task, but it is a reminder that the scanner owns a non-thread-safe Foundation dependency.

## Review Fix Addendum

I moved the directory enumeration, filtering, and sorting work onto a background queue so `scan(containing:)` keeps the same async API without doing the heavy directory walk on the caller's executor.

### Verification Run

- `swift test --filter DirectoryScannerTests`
- `swift test`

### Output Summary

- `DirectoryScannerTests`: 2 tests passed, 0 failures
- Full suite: 6 tests passed, 0 failures

### Notes

- Added a focused regression test that calls `DirectoryScanner.scan(containing:)` from `@MainActor` and confirms directory enumeration happens off the main thread.
