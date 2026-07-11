# Multiple Image Windows Design

## Goal

Allow ImageView to display multiple independent image windows. The application launches with one empty image window, reuses that window for the first opened image, creates a new window for every subsequent image URL, and terminates when the last image window closes.

## Window Opening Rules

At normal launch, ImageView creates exactly one empty `MainWindowController` and shows its window.

All URL sources use one opening pipeline:

- Finder and Launch Services open events.
- **File → Open…**.
- **Open Recent**.

The first URL reuses an existing empty startup window when one is available. Every remaining URL creates a new `MainWindowController`, opens that URL, and shows the new window. If Launch Services delivers multiple URLs in one event, the first URL may reuse the startup window and every other URL receives its own window.

Once the startup window has been assigned a URL, it is no longer considered empty even if decoding later fails. A failed image remains in its assigned window with the existing error presentation; another URL never replaces it automatically.

Each window has an independent `ViewerViewModel`, directory sequence, selection, zoom, pan, crop/edit state, unsaved-change flow, overlays, and title.

## Ownership and Lifecycle

`AppDelegate` replaces its single `mainWindowController` reference with an ordered collection of live `MainWindowController` instances. It also tracks the most recently active image controller for menu routing when a non-image utility window is key.

Window controllers notify `AppDelegate` when their windows become key and when they close. Closing a window removes only that controller from the live collection. The other image windows and their state remain unchanged.

When the live image-controller collection becomes empty, `AppDelegate` requests application termination exactly once. The Settings window does not keep ImageView alive and closes as part of application termination. `applicationShouldTerminateAfterLastWindowClosed` remains `true` as a system-level fallback, while the explicit empty-collection rule enforces the product requirement even when Settings is still visible.

The delegate must distinguish a real image-window close from temporary window lifecycle transitions and guard against duplicate termination requests.

## Launch Events

Before `applicationDidFinishLaunching`, incoming URLs are accumulated in order rather than reduced to one URL. At launch completion:

1. Create and show the empty startup window.
2. Install menus.
3. Open all pending URLs through the shared URL pipeline.

After launch, each `application(_:open:)` event passes its full ordered URL array through the same pipeline.

## Menu Routing

Image and viewer menu actions must target the correct image window:

1. Use the controller whose window is currently key when it is an image window.
2. If Settings is key, use the most recently active live image controller.
3. If no image controller exists, image-specific actions have no target and remain disabled while termination proceeds.

Switching image windows updates menu targets and validation immediately. **File → Open…**, **Open Recent**, Settings, appearance, Quit, and Help remain app-level actions owned by `AppDelegate`.

Opening a URL from **File → Open…** or **Open Recent** does not replace the current image; it follows the shared new-window rule.

## Recent Items

Every successfully decoded URL is noted through `NSDocumentController.shared.noteNewRecentDocumentURL`. Each window receives the same success callback implementation, so successful opens from any window rebuild the shared Open Recent menu. Decode failures are not added.

## Unsaved Changes and Closing

Each controller keeps its existing unsaved-change confirmation. Canceling a close leaves that controller in the live collection. Saving or discarding closes only the requested window. Application termination begins only after the last image window actually closes.

If the user quits from the application menu while multiple windows have unsaved changes, normal AppKit termination and each window's existing close handling remain authoritative; this feature does not add a new consolidated quit dialog.

## Error Handling

- A failed decode stays isolated to its assigned window.
- Closing one failed window does not affect successful windows.
- Duplicate URLs are allowed and create independent windows after the startup-window reuse rule.
- An empty URL array creates no additional window.
- A close callback for an unknown or already-removed controller is ignored.

## Testing

Tests use injected controller creation and termination seams so they do not open visible production windows or terminate the XCTest host.

Coverage includes:

- Launch creates one empty image window.
- The first URL reuses the startup window.
- Subsequent and batched URLs create one controller per URL.
- Pre-launch URLs retain their full order and are all opened after launch.
- Duplicate URLs create independent windows.
- Closing one controller removes only that controller.
- Closing the final image controller requests termination once, even with Settings present.
- Canceling a close does not remove a controller.
- Key image windows and the most recently active image window receive menu routing correctly.
- Settings becoming key does not lose the last active image target.
- Successful opens from every controller update the shared recent-items behavior.
- Independent controller/view-model instances do not share navigation, transform, or edit state.
- Existing single-window viewer tests continue to pass.

Final verification runs the complete Swift test suite and the Release application build script.

## Out of Scope

- Migrating the app to `NSDocument`.
- Window tabbing or tab restoration.
- Reopening windows after relaunch.
- Persisting window positions or image sessions.
- Consolidating multiple unsaved-change prompts during Quit.
- Reusing a nonempty image window for a later Open command.
