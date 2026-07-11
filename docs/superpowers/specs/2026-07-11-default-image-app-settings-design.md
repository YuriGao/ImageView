# Default Image Application Settings Design

## Goal

Add a file-association section to the existing ImageView Settings window. Users can select common image formats and set ImageView as their default application for all selected formats with one action. Formats that are not selected remain unchanged.

## Scope

The default list contains JPEG, PNG, GIF, WebP, and HEIC. A **Show All Formats** control reveals TIFF, BMP, HEIF, AVIF, and SVG, covering every format already declared by ImageView.

This feature only assigns ImageView as the default application. It does not restore Preview, assign another application, or change unselected formats. Checkbox selections are session-only UI state and are not persisted.

## Settings Window UI

Add a **File Associations** section to the existing AppKit settings window and enlarge the window to fit the new controls. The section uses native AppKit controls and follows the application's selected light, dark, or system appearance.

Each visible format row contains:

- A checkbox for including the format in the next operation.
- The human-readable format name and its filename extensions.
- Current default-application status.

When ImageView is already the default, the row displays **Default: ImageView**. Otherwise it displays the current default application's localized name when available. An unavailable result uses a neutral **Default application unknown** status rather than treating the query as an operation failure.

The section includes:

- **Select Common Formats**, which selects JPEG, PNG, GIF, WebP, and HEIC without clearing any additional selected formats.
- **Show All Formats**, which expands or collapses the five less-common formats without changing their selection.
- **Set ImageView as Default**, which is disabled when no format is selected or while an operation is running.

Opening the settings window refreshes current system associations. Checkboxes begin unchecked each time the window controller is created; reopening the same window retains its current session selection but never infers checkbox state from the current default application.

## Architecture

Introduce a focused `DefaultApplicationService` abstraction. It owns all interaction with the macOS default-application APIs and provides two operations:

1. Query the current default application for a `UTType`.
2. Set a supplied application bundle URL as the default for a `UTType`.

The production implementation uses `NSWorkspace`'s macOS 12+ content-type APIs. ImageView's minimum deployment target is macOS 14, so no legacy Launch Services fallback is needed. The deprecated `LSSetDefaultRoleHandlerForContentType` API and command-line utilities are explicitly excluded.

`SupportedImageFormat` remains the sole mapping between supported formats and `UTType`. Presentation metadata such as localized display names and extension labels may be supplied by a small settings-specific formatter, but it must not duplicate content-type identifiers.

`PreferencesWindowController` owns the visible rows, temporary selections, expanded state, progress state, and result messages. It consumes the service through an injectable protocol so behavior can be tested without changing real system associations.

## Apply Flow

When the user clicks **Set ImageView as Default**:

1. Collect only checked formats.
2. Validate that the running executable belongs to a usable `.app` bundle and obtain that bundle URL.
3. Disable mutation controls and show in-progress state.
4. Process each selected format through `DefaultApplicationService`.
5. Keep successful assignments even if another assignment fails; there is no rollback.
6. Leave failed formats checked, uncheck successful formats, and show a summary.
7. Refresh current default-application status for all visible formats.

System associations are global external state, so operations are performed asynchronously and UI updates return to the main actor. Formats may be processed sequentially to keep result attribution deterministic and avoid concurrent Launch Services mutations.

## Errors and Feedback

Possible failures include an invalid application bundle URL, a missing `UTType`, or an error returned by `NSWorkspace`.

- An invalid application bundle prevents the entire operation and displays: **Launch ImageView from ImageView.app and try again.**
- A missing content type fails only that format.
- An `NSWorkspace` error is attached to the affected row using a short localized message.
- Partial success displays **Set X formats; Y failed.** Successful changes are not rolled back.
- Total success displays **ImageView is now the default for X formats.**
- Failed formats remain selected for immediate retry.

The query path is read-only and must not block opening the settings window. A query failure produces the neutral unknown status.

## Localization

All new section titles, buttons, format status text, progress text, summaries, and user-facing errors are localized in English and Simplified Chinese through the existing `AppStrings` mechanism.

## Testing

Unit tests cover:

- The five common formats and the complete ten-format ordering.
- Expand/collapse behavior without selection loss.
- Selecting common formats without clearing extra selections.
- Disabled apply state with no selection and during an operation.
- Only checked formats being passed to the service.
- All-success, partial-failure, and all-failure summaries.
- Successful formats becoming unchecked while failures remain selected.
- Current default-application status refresh after application.
- Safe failure when no valid `.app` bundle URL is available.
- English and Simplified Chinese strings.
- Service-to-`NSWorkspace` mapping through a narrow test seam without changing the test machine's real defaults.

Final verification runs the full Swift test suite and the existing Release application build script.

## Out of Scope

- Assigning formats to Preview or any third-party application.
- Reverting or editing unselected formats.
- Persisting checkbox selections.
- Adding a separate settings window or File-menu entry.
- Shelling out to third-party file-association tools.
