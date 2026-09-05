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
