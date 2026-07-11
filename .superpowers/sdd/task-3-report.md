Task 3 Report: Navigation State and Sequence Updates

Implementation
- Added `Sources/ImageViewCore/Navigation/NavigationState.swift`.
- Implemented `NavigationState` with natural-sort ordering on initialization, current item tracking by URL, next/previous movement, current-item removal, and URL replacement with re-sorting.
- Kept the storage and index internal so the type stays small while remaining testable via `@testable import`.
- Added `Tests/ImageViewCoreTests/NavigationStateTests.swift` with the three scenarios from the task brief.

Tests / Output
- First verification run: `swift test --filter NavigationStateTests`
  - Failed as expected before production code existed with `cannot find 'NavigationState' in scope`.
- After implementation:
  - `swift test --filter NavigationStateTests` passed.
  - `swift test` passed.
- Final suite result: 9 tests passed, 0 failures.

TDD Evidence
- Wrote the tests first.
- Verified the initial red state by running the filtered test suite and confirming the missing-type compiler failure.
- Added the minimal production implementation to satisfy the tests.
- Re-ran the filtered suite and the full package suite until both were green.

Files Changed
- `Sources/ImageViewCore/Navigation/NavigationState.swift`
- `Tests/ImageViewCoreTests/NavigationStateTests.swift`

Self-Review
- Behavior matches the brief: sorted sequence, open-file selection, nearest usable removal behavior, and resorting after replacement.
- URL matching uses exact URL first and standardized file URL as a fallback, which is helpful for file-path normalization.
- No unrelated files were touched.

Concerns
- None at present. The implementation and tests are green, and I did not need to modify any shared interfaces.

Review Fix Addendum
- Updated `NavigationState` to `public struct NavigationState: Equatable, Sendable`.
- Exposed `items` and `currentIndex` as `public private(set)` so other modules can read navigation sequence state without mutating it.
- Re-ran `swift test --filter NavigationStateTests` and `swift test`; both passed.
