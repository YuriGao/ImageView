# Filmstrip Visibility Eligibility Design

## Goal

Prevent the filmstrip overlay from appearing when no image is loaded or while the image is zoomed beyond its fit-to-window scale.

## Eligibility

The filmstrip may appear only when all conditions are true:

- The filmstrip setting is enabled.
- A decoded image is currently loaded.
- The canvas scale is less than or equal to `1.01`.
- Pointer activity requests the overlay.

`1.01` matches the canvas's existing tolerance for distinguishing fit-to-window from a zoomed image.

## Transitions

- Clear or failed image loading hides the filmstrip immediately and cancels its timer.
- Increasing canvas scale above `1.01` hides the filmstrip immediately, even while the pointer is over it.
- Returning to scale `1.01` or below does not reveal the filmstrip automatically; the next pointer movement reveals it.
- Navigating between images preserves these rules throughout preview and full-resolution loading.
- Existing delayed auto-hide and hover suppression remain unchanged while the filmstrip is otherwise eligible.

## Architecture

- Extend the existing pure filmstrip eligibility helper in `MainWindowController` to accept enabled state, loaded-image state, canvas scale, and pointer activity.
- Use the same helper from pointer-driven reveal logic and tests.
- React to `currentImage` and canvas transform updates by hiding immediately when eligibility is lost.

## Testing

- Verify disabled setting, no loaded image, zoom above `1.01`, and inactive pointer each prevent display.
- Verify a loaded image at fit scale with pointer activity permits display.
- Verify the exact `1.01` tolerance remains eligible and values above it do not.
- Run the complete unit test suite and production app build.
