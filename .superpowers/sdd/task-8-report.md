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

Re-review discard semantics fix:
- `ViewerViewModel` now keeps a persisted baseline image for the current item, refreshes that baseline on open/display/save, and uses it to restore the original pixels before clearing pending edits.
- `discardCurrentEdits()` now returns success/failure. If restore fails, it leaves the item dirty and reports `无法还原原始图片`; if restore succeeds, it clears dirty state only after the original image is back on screen.
- `MainWindowController` now only proceeds with discard-driven transitions when the restore succeeds, including window-close handling.
- Updated `ViewerViewModelTests` so discard-in-place restores the original decoded image, and added a regression that discarding at the end-of-list boundary leaves the original image visible with `hasUnsavedEdits == false`.
- Verification: `swift test --disable-sandbox --filter ViewerViewModelTests`, `swift test --disable-sandbox --filter MainWindowControllerTests`, `swift test --disable-sandbox`, and `swift build --disable-sandbox` all passed using workspace-local absolute module cache overrides.

Reachability re-review fix:
- Added a minimal `Edit` menu in `AppDelegate` with reachable commands for rotate clockwise, rotate counterclockwise, flip horizontal, flip vertical, save edits, and discard edits; all targets reconnect to `MainWindowController` when the main window is created.
- Added focused `@objc` menu actions in `MainWindowController` that route edit commands into the existing `ViewerViewModel` editing APIs, while keeping the existing unsaved-changes guard for destructive transitions like open/navigation/rename/trash/close.
- Tightened menu validation by mapping selectors to explicit menu-command cases, enabling edit commands only when an image is displayed and enabling save/discard only when there are unsaved edits.
- Expanded `MainWindowControllerTests` to cover selector-to-operation routing and menu-command availability seams without disturbing the existing controller and view-model coverage.
- Verification: `swift test --disable-sandbox` passed (48 tests) and `swift build --disable-sandbox` passed in the worktree after rerunning outside the managed sandbox so SwiftPM could access its module cache.
