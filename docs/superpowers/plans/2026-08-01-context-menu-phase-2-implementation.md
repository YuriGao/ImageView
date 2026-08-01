# Image Context Menus Phase 2 Implementation Plan

## Goal

Extend contextual image actions beyond the single-image canvas to the filmstrip, continuous reading view, and folder browser while guaranteeing that every command applies to the item that was right-clicked.

## Scope

### Filmstrip

Right-clicking a thumbnail must not navigate immediately. The menu targets that thumbnail and contains:

- Show This Image (disabled for the current thumbnail)
- Copy Path
- Reveal in Finder
- Rename…
- Move to Trash

Editing and zoom commands remain exclusive to the main image canvas.

### Continuous Reading

The document view resolves the page under the pointer and supplies both its `ImageItem` and decoded bitmap, when available. The menu contains:

- Show in Single Image View
- Copy Image (enabled only when that page is decoded)
- Copy Path
- Reveal in Finder
- Rename…
- Move to Trash

Commands must target the clicked page rather than the current scroll focus. Choosing a destructive or renaming action may make the target current first so the existing unsaved-edit and navigation safety paths remain authoritative.

### Folder Browser

Right-click selection follows macOS collection conventions:

- Clicking an unselected item replaces the selection with that item.
- Clicking an already selected item preserves the multi-selection.
- Clicking blank space returns no menu and does not change selection.
- No menu is available while a batch operation is running or the content grid is unavailable.

For one selected item the menu contains Open, Copy Path, Reveal in Finder, Move to Folder…, Rename…, and Move to Trash. For multiple selected items it contains pluralized Copy Paths, Reveal Items in Finder, Move Items…, Batch Rename…, and Move Items to Trash. Open is omitted for multiple selection.

## Architecture

1. Each view owns hit testing and exposes a menu-provider callback carrying an explicit target.
2. `MainWindowController` owns menu construction and application actions.
3. Filmstrip and continuous-reading file actions accept explicit `ImageItem` values; they do not read the current item accidentally.
4. Folder-browser menus reuse its existing selection model and batch-operation callbacks.
5. Closure-backed AppKit action dispatchers are retained through each menu item's `representedObject` for the full menu-tracking lifetime.
6. Existing confirmation, unsaved-edit, mutation migration, and batch conflict flows remain the only paths that rename, move, or delete files.

## Files

- `Sources/ImageViewApp/Viewer/FilmstripView.swift`
- `Sources/ImageViewApp/Viewer/ContinuousReadingView.swift`
- `Sources/ImageViewApp/FolderBrowser/FolderBrowserView.swift`
- `Sources/ImageViewApp/MainWindowController.swift`
- `Sources/ImageViewApp/Localization/AppStrings.swift`
- `Sources/ImageViewApp/Resources/*/Localizable.strings`
- Corresponding view and controller tests

## Verification

- Filmstrip right-click reports the clicked thumbnail without selecting it.
- Continuous-reading hit testing reports the clicked page and no page in inter-page gaps.
- Folder-browser right-click implements single- and multi-selection rules.
- Menus contain the expected single/plural commands and target the selected URLs.
- Copying multiple paths writes one absolute path per line.
- Batch-operation state suppresses the folder context menu.
- Existing single-image context menu behavior remains unchanged.
- All localization-key tests and the complete Swift test suite pass.
