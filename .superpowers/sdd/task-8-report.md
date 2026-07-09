Status: implemented, verified, committed
Commits created: 1 (current HEAD at submission)
Test summary: `swift test --disable-sandbox --filter ImageEditingServiceTests` passed (2 tests), `swift test --disable-sandbox` passed (40 tests), and `swift build --disable-sandbox` passed with workspace-local cache env.
Concerns: SwiftPM still prints readonly user-cache warnings in this managed sandbox, but the required test/build commands completed successfully using workspace-local module cache paths.
Report file: /Users/gaoyinrui/Documents/Codex/ImageView/.worktrees/imageview-v1/.superpowers/sdd/task-8-report.md

Fix follow-up (post-review):
- Added a real unsaved-edits guard in `MainWindowController` for open, previous/next, filmstrip selection, rename, trash, and window close. Save failure now keeps the current image in place.
- Made `ViewerViewModel.saveCurrentEdits()` return success/failure and added a non-reloading discard helper so controller routing can decide whether to proceed.
- Corrected rotation direction semantics in `ImageEditingService`, and changed `.heif` writes to use `public.heif` only when ImageIO exposes a matching destination writer; otherwise `.heif` save is rejected as unsupported.
- Expanded tests with pixel-level mirror/crop/rotation coverage plus focused controller/view-model guard-state assertions.
- Verification: `swift test --disable-sandbox --filter ImageEditingServiceTests`, `swift test --disable-sandbox --filter MainWindowControllerTests`, `swift test --disable-sandbox --filter ViewerViewModelTests`, `swift test --disable-sandbox`, and `swift build --disable-sandbox` all passed using temp module-cache env overrides in the managed sandbox.
