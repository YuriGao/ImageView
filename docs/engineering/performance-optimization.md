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
