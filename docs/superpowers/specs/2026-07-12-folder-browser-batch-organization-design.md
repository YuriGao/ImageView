# Folder Browser and Batch Organization Design

## Context

ImageView currently works as a lightweight native macOS image viewer: open an image quickly, browse the current directory naturally, zoom and edit lightly, then save or manage the current file. Recent fixes added reliable empty and error state recovery, including returning from unsupported file selections to a usable open state.

The next product step is to improve everyday folder-level organization without turning ImageView into a library app. The intended audience is a Mac user who wants a fast default image viewer with enough folder browsing and batch cleanup to avoid jumping back to Finder for common tasks.

## Product Direction

The feature should keep ImageView positioned as a lightweight default image viewer, not a photo manager. It must not create a persistent image library, import photos into a database, or scan unrelated folders in the background.

The recommended model is a current-folder session:

- The app only works with the folder the user opened or the folder containing the current image.
- Folder state is in memory for the window lifetime.
- Search, filtering, sorting, selection, and scroll position belong to that session.
- Closing the window discards the session state.
- Existing single-image open, browsing, editing, and saving behavior remains the primary path.

## User Entry Points

Add a folder browser mode inside the existing window model.

Entry points:

- `File > Browse Folder...` opens a system folder picker and enters folder browser mode.
- The empty state includes a secondary `Browse Folder...` action.
- The image viewer titlebar includes a compact grid button that toggles between the current image and that image's containing folder grid.

The normal Finder double-click path still opens the image directly. It must not force the user through a grid first.

## Folder Browser Mode

The folder browser shows a grid of supported image files in the current folder. Each cell shows a thumbnail and filename. File dimensions and size can load lazily after the visible thumbnails appear.

Selection behavior should follow macOS expectations:

- Click selects one item.
- Command-click toggles an item.
- Shift-click extends the range.
- Command-A selects all currently filtered items.
- Double-click or Return opens the selected image in the same window.
- Returning from image view to the grid restores the prior scroll position and selection.

The grid toolbar provides lightweight organization controls:

- Search by filename.
- Sort by name, modified date, and file size.
- Filter by supported image type.
- Batch actions for selected items.

The grid should not include ratings, albums, tags, people, memories, or other library concepts.

## Batch Actions

The first version supports three high-value organization actions.

### Move to Trash

The user can move selected images to the system Trash through the toolbar or Delete key. The app shows one confirmation with the selected count before execution. Files are never permanently deleted by this command.

After a successful trash operation:

- Removed files disappear from the folder session.
- Selection moves to the nearest remaining item where practical.
- Failed items remain selected.
- A short result message reports success and skipped or failed files.

### Move to Folder

The user can move selected images to another folder through a system folder picker.

Conflict handling must be conservative:

- Never silently overwrite an existing file.
- If conflicts exist, show the conflicting names before execution.
- Offer `Skip Conflicts` and `Keep Both` as safe choices.
- Do not offer overwrite in the first version.

After execution, moved files disappear from the source folder session. Failed or skipped files remain visible and selected.

### Batch Rename

Batch rename uses a modal sheet with preview. The first version supports a simple pattern:

- Base name plus sequence number.
- Start number defaults to `1`.
- Padding defaults from the selected count, such as `01` for 42 files.
- Each file keeps its original extension.
- A preview shows old name to new name before execution.

Validation runs before the action can execute:

- New names cannot be empty.
- New names cannot duplicate each other.
- New names cannot conflict with unselected files in the same folder.
- New names cannot contain invalid macOS filename characters.

The rename operation should avoid transient name collisions by planning the full rename set before applying changes.

## Operation Feedback and Recovery

Batch operations show progress for long-running work and allow cancellation for files that have not started processing. Completed file operations remain completed after cancellation.

All operation results should be explicit:

- Complete success: show a compact success message.
- Partial failure: keep failed files selected and show a list of failed filenames with reasons.
- Full failure: leave the folder session intact and keep the selection.

No operation failure may trap the user in an error-only screen. From any failure state, the user must be able to return to the folder grid, choose a different file, open the picker again, or continue browsing.

Undo support in the first version should be limited:

- Move to Trash can attempt to restore files from Trash when macOS provides enough information.
- Batch rename can reverse the recorded rename mapping.
- Move to another folder should not promise undo in the first version because destination folder state and permissions may change after the operation.

## Proposed Implementation Boundaries

### FolderSession

Owns the in-memory folder state:

- Folder URL.
- Supported image file list.
- Sort mode.
- Search text.
- Type filter.
- Selection.
- Current grid scroll position.

It does not perform file system mutations.

### FolderBrowserView and Controller

Owns the grid UI and user interaction:

- Thumbnail grid.
- Filename labels.
- Multi-selection.
- Toolbar controls.
- Double-click or Return to open image view.
- Grid/image mode restoration.

It consumes `FolderSession` and delegates mutations to the batch operation service.

### BatchFileOperationService

Owns file system mutations:

- Move to Trash.
- Move to destination folder.
- Batch rename.
- Conflict detection.
- Per-file progress.
- Cancellation.
- Structured result reporting.

The UI should receive operation results rather than interpreting file system errors directly.

### ThumbnailProvider

Owns thumbnail loading for the folder grid:

- Reuse the existing image decoding and cache path where practical.
- Load thumbnails asynchronously.
- Prioritize visible cells and nearby cells.
- Cancel work for cells that scroll far out of view.
- Avoid blocking the main window for large folders.

## Existing Behavior Compatibility

The following paths must keep their current behavior:

- Finder double-click opens a single image directly.
- Dragging a supported image opens it directly.
- `Open...` for images opens the selected image directly.
- Same-folder next and previous image browsing keeps working.
- Zoom, pan, fullscreen, filmstrip, edit, save, rename current file, trash current file, reveal in Finder, and copy path keep working from image view.
- Unsupported file handling still returns to a recoverable state.

## Testing Plan

Add tests proportional to the file-system and UI-state risk:

- Supported-format scanning includes only supported image files.
- Filename search, sort, and type filter compose correctly.
- Multi-select state behaves correctly after filtering and sorting.
- Move to Trash removes successful files from the session and preserves failed selection.
- Move to folder never silently overwrites conflicts.
- Batch rename preview preserves extensions and blocks duplicates or conflicts.
- Batch rename handles intra-selection name collisions safely.
- Failed operations leave the user able to continue from the grid.
- Opening an image from the grid and returning restores scroll position and selection.
- Thumbnail loading is asynchronous and can be cancelled for off-screen cells.

Manual verification should include a large folder, mixed supported and unsupported files, same-name conflict cases, and a failed permission case.

## Out of Scope

The first version deliberately excludes:

- Persistent photo library or database.
- Recursive folder import.
- Ratings, tags, albums, people, or timeline views.
- Image conversion, resizing, compression, or watermarking.
- Permanent delete.
- Silent overwrite.
- Guaranteed undo for moving files between arbitrary folders.

These exclusions keep the feature aligned with ImageView's lightweight viewer positioning.
