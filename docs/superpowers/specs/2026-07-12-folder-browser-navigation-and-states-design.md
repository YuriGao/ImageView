# Folder Browser Navigation and States Design

## Context

The folder browser currently reloads the entire collection whenever selection changes. Each reload clears visible thumbnails before loading them again, which causes a flash on ordinary clicks. Folder cells also have no selected appearance, so a logical selection is not visible.

The title-bar grid button is one-way: it opens or reloads the current image's folder even when the folder browser is already visible. Opening an image from the grid hides the folder browser but records no page-navigation origin, so the user cannot return to the same grid state.

The grid also renders no dedicated loading, empty, filtered-empty, or folder-load-failure presentation.

## Goals

- A single click selects an image without reloading thumbnails and shows a native-feeling selection highlight.
- A double-click or Return opens the selected image in the viewer.
- The title-bar grid button toggles between the current folder grid and the current image viewer.
- Back and Forward navigate page history between the live folder grid and image viewer; they do not replace Previous Image and Next Image.
- Returning to the grid preserves its search, type filter, sort mode, selection, and scroll position.
- Loading, empty-folder, filtered-empty, and folder-load-failure states are explicit and recoverable.

## Interaction Model

### Grid Selection and Opening

- Single-click updates selection only. It must not reload the collection or restart thumbnail requests.
- Selected cells use an appearance-adaptive background, border, and filename emphasis that remain legible in light and dark mode.
- Command-click, Shift-click, and Command-A retain the existing macOS multi-selection behavior.
- Double-click and Return open the first selected image in the same window.

### Grid Button

- In an image opened from the current folder session, clicking the grid button shows that existing grid without rescanning.
- In the folder grid, clicking the same button restores the live image viewer that led to the grid.
- When an image was opened directly and no folder session exists, clicking the grid button scans its containing folder once and establishes the grid/viewer relationship.
- The button tooltip and accessibility label describe the destination for the current mode rather than always saying "Browse Current Folder."
- Pointer hover gives the button a subtle appearance-adaptive background and stronger symbol tint; mouse-down adds a compact pressed response. The feedback must not resize or shift the title bar.

### Back and Forward

- Add compact Back and Forward buttons to the title bar, separate from the grid button.
- Back, Forward, and Grid use one consistent hover, pressed, focus, and disabled-state treatment. Disabled navigation buttons remain visibly unavailable and do not show an active-looking hover response.
- The first supported history is intentionally lightweight: one live folder route and one live viewer route in the current window.
- Opening a grid item creates a Viewer route and enables Back.
- Back restores the same live FolderSession and collection view. Forward restores the same live viewer state without decoding or scanning again.
- Opening another grid item after going Back replaces the Forward destination.
- Directly opened images have no synthetic Back destination.
- Previous Image and Next Image continue to navigate images inside the viewer and do not create page-history entries.
- The first version uses visible title-bar controls only. Existing keyboard shortcuts conflict with rotation and image navigation, so no new history shortcuts are added in this change.

## State and Architecture

### FolderBrowserViewModel

Introduce a presentation state derived from explicit load data rather than from an empty item array:

- `loading`
- `content`
- `emptyFolder`
- `filteredEmpty`
- `loadFailed(message)`

Keep folder-load failure separate from batch-operation messages. Preserve the last requested folder URL so Retry can run the same scan.

Selection changes remain part of FolderSession, but the controller must update selection in the collection without calling `reloadData()`. Item/filter/sort changes can update collection content; selection-only changes use targeted selection synchronization.

### FolderBrowserView

Keep the toolbar visible for normal, loading, content, and filtered-empty states. Add one centered content-state view above the collection area:

- Loading: progress indicator and localized loading text.
- Empty folder: concise explanation and `Choose Another Folder`.
- Filtered empty: concise explanation and `Clear Filters`.
- Load failure: localized error text with `Retry` and `Choose Another Folder`.

The collection remains the content surface and is hidden only when a non-content presentation owns the area. Batch controls are disabled when there is no actionable selection or while loading/operating.

### MainWindowController

Add a small route coordinator that owns the current content route and Back/Forward availability. It switches existing live views rather than recreating their models.

`FolderSession.lastOpenedItemID` records the image associated with the grid/viewer transition. The controller updates or clears the viewer route when batch operations remove or rename its target. Existing unsaved edits stay live when temporarily returning to the grid; no save prompt is shown for a non-destructive view switch.

## Recovery Behavior

- `Clear Filters` resets filename search and type filtering to All Types, then returns to content or empty-folder state.
- `Choose Another Folder` opens the existing folder picker pipeline.
- `Retry` rescans the same folder and transitions through Loading.
- A failed retry remains recoverable and does not replace the grid with a terminal error screen.
- Returning to the grid never rescans solely because of navigation.

## Testing

Use TDD with focused failures before each production change.

- Selection updates do not reload collection items or restart thumbnails.
- A selected cell has an explicit selected appearance and clears it when deselected.
- Single-click selects; double-click and Return open exactly once.
- The grid button toggles both directions without rescanning an existing session.
- Back restores the same session, filter, sort, selection, and scroll position.
- Forward restores the live viewer; opening another item clears the prior forward destination.
- Direct image opens do not invent folder history.
- Previous/Next Image do not mutate page history.
- Loading, empty-folder, filtered-empty, and load-failure presentations are distinct.
- Clear Filters, Retry, and Choose Another Folder invoke the correct recovery callbacks.
- English and Simplified Chinese strings cover every new label, tooltip, and accessibility description.
- Title-bar Grid, Back, and Forward controls expose stable normal, hover, pressed, focus, and disabled visual states without layout movement.

Manual verification uses temporary or read-only system images and covers light/dark appearance, title-bar hover and pressed feedback, single/double click, grid toggle, Back/Forward availability, search/type empty results, empty folder, and simulated folder-load failure. It must not delete, move, or rename user images.

## Out of Scope

- A general multi-folder browser-history stack.
- New keyboard shortcuts for page history.
- Replacing Previous/Next Image navigation.
- Persistent folder sessions across window closure or app restart.
