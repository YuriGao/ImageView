# ImageView performance optimization

Scope, in implementation order:

1. Background image editing, undo replay, save and metadata; bounded work, busy state and safe transitions.
2. Cancellation-aware shared image loads and visible-image decode priority.
3. Bounded background animated frame prefetch with playback deadlines.
4. Stable continuous-reading dimensions, cached layout and indexed visible-page lookup.
5. Reuse folder sort/search work and update grid changes incrementally.
6. Run tests on pushes/PRs and before packaging; cover interactive performance regressions.
7. Extract window responsibilities and complete viewer error/title localization.

Validation and measured results will be recorded alongside each completed change. Optional camera RAW fixture tests require external samples and must remain explicitly reported when skipped.

## 1. Background edits and metadata

- Image edits, replay and atomic saves use a serial bounded executor. The window displays progress and prevents conflicting transitions; save-and-close waits for success.
- Histories compose consecutive rotations/reflections into one bitmap draw, retaining crop boundaries. Failed replay keeps undo/redo history intact.
- Metadata reads run on a separate actor and reuse a bounded cache keyed by file version; dimensions update immediately.
- Validation: 484 tests, 480 passed and 4 optional RAW tests skipped. Added pixel equivalence across 64 transform combinations, identity allocation avoidance, background responsiveness/stale-result protection and failed-undo history preservation.

## 2. Shared-load cancellation and decode priority

- Cache requests now track consumers individually. Cancellation returns promptly, cancels the underlying request only after its last consumer leaves, and cannot remove/repopulate a replacement request.
- Visible requests promote an existing queued prefetch using a shared operation priority token; background neighbors keep low queue priority.
- Validation: 488 tests, 484 passed and 4 optional RAW tests skipped. Added last/shared-consumer cancellation, invalidation/replacement races and queued-priority ordering coverage.

## 3. Animated frame prefetch

- AnimationPlayer owns monotonic playback deadlines and at most two upcoming frames. Frame reads use a process-wide executor limited to two workers; shared frame sources serialize their ImageIO access.
- Look-ahead is limited to 64 MiB, allowing one oversized upcoming frame when required for playback. Replacing an image cancels prefetch and ignores late results.
- Validation: 491 tests, 487 passed and 4 optional RAW tests skipped. Added off-main frame reads, buffer bounds over repeated advancement, stale source replacement and timing compensation tests.

## 4. Continuous-reading geometry

- Known aspect ratios survive bitmap eviction. Geometry is cached by page order/dimensions and viewport width; first-time unknown dimensions still refine their placeholder when discovered.
- Page ID lookup is indexed, focused-page and visible-range lookup use binary search, and drawing visits only the visible range. Cancelled page-window loads stop requesting neighbors.
- Validation: 493 tests, 489 passed and 4 optional RAW tests skipped. Added bitmap eviction geometry preservation and 1,000 repeated geometry/visibility lookups in a 10,000-page directory without rebuilding layout.

## 5. Folder search and grid updates

- FolderSession caches sorted items and folded filename search keys. Search/format changes filter the sorted list without sorting it again; item and sort changes rebuild the appropriate caches.
- Grid filters apply insert/delete batches, preserve selection by ID and refresh accessibility positions. AppKit may replace cell objects; cached thumbnails are reused without another decode. Initial population, empty results and wholesale sort changes use one reload.
- Validation: 32 targeted folder tests passed, including accent/case handling, rename index invalidation, selection preservation, incremental item counts and no repeated decode for retained thumbnails.
- Same local optimized-build synthetic benchmark, 10,000 items: five queries took 4.12–5.98 ms each versus 9.87–11.72 ms before changes (roughly halved). This measures model filtering, not end-to-end UI frame time.

## 6. Continuous integration and optimized checks

- Pushes and PRs run the full suite plus an optimized build of interactive/cache/layout regressions. Release packaging depends on successful tests and keeps write permissions only on the packaging job.
- Existing DEBUG-only UI test hooks also support the explicit TESTING flag so optimized tests compile without enabling general DEBUG behavior in release builds.
- Validation: actionlint passed; 121 optimized interactive/performance tests passed. Remote validation is recorded by the pull request checks.

## 7. Window responsibilities and localization

- File/edit actions, menus and presentation logic now live in three focused MainWindowController extensions. The primary controller file shrank from 3,155 to 2,000 lines without changing menu selectors.
- Filmstrip/page-control auto-hide share a cancellation-aware scheduler with generation guards for stale animation completions.
- Viewer errors, processing accessibility text and edited titles use English/Simplified Chinese resources. Localization tests explicitly cover both languages rather than assuming the host language.

## Final lifecycle audit

- An atomic save owns its worker until completion even if its caller is cancelled. Busy/unsaved state remains active until that worker finishes, and application termination is deferred by rejecting quit while a window owns an image operation.
- Full debug validation: 498 tests, 494 passed and 4 optional RAW tests skipped. Added save-cancellation ownership and quit-during-operation coverage.

## Final validation

- Full debug and optimized release suites each executed 498 tests: 494 passed, 4 optional camera RAW fixture tests skipped, zero failures.
- Release app bundle built successfully and passed `codesign --verify --deep --strict`.
- `actionlint` passed for the updated workflow.
- [2026-09-06 memory benchmark](../assets/performance/memory-baseline-2026-09-06-064318.md): all five existing gates passed (small image 128.5 MiB, large image 906.6 MiB, animation 163.0 MiB, thousand-image grid 155.9 MiB, filmstrip 166.0 MiB peak RSS). These are six-second launch samples, not a substitute for long-running interaction profiling.
- GitHub's check results on the pull request provide remote validation of the final pushed revision.
