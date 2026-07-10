# Floating Page Controls Design

## Goal

Add discoverable, clickable previous and next page controls that appear over the left and right sides of the image canvas without consuming title-bar or status-bar space.

## Layout and Appearance

- Place one 44 x 64 point control near each horizontal edge of the image canvas.
- Vertically center both controls within the canvas area.
- Use the system `chevron.left` and `chevron.right` symbols.
- Use an appearance-adaptive system background, a separator-colored one-physical-pixel border, restrained shadow, and an 8-point-or-smaller corner radius.
- Keep the controls above the canvas and below editing overlays where necessary.

## Visibility

- Reveal both controls whenever the pointer moves within the window's content area.
- Reveal both controls whenever navigation succeeds, regardless of whether it came from a button, keyboard, menu, or trackpad.
- Fade the controls out after 1.5 seconds without relevant interaction.
- Cancel auto-hide while the pointer is over either control. Restart the delay after the pointer leaves.
- Hide both controls when no image is open, only one image exists, or crop editing is active.

## Interaction and Boundary States

- Clicking the left control navigates to the previous image.
- Clicking the right control navigates to the next image.
- Disable the left control on the first image and the right control on the last image.
- Disabled controls remain visible during the normal reveal period so the sequence boundary is understandable.
- Controls must not intercept canvas interactions outside their visible button bounds.

## Architecture

- Add a focused AppKit view that owns the two buttons, dynamic appearance, pointer tracking, and button callbacks.
- `MainWindowController` owns visibility timing because it already coordinates pointer movement, navigation, crop state, and the navigation model.
- Route button clicks through the existing `navigateToPreviousImage()` and `navigateToNextImage()` methods so all navigation paths keep the same unsaved-edit handling and transition behavior.

## Testing

- Verify visibility eligibility for zero, one, and multiple images and for crop mode.
- Verify first, middle, and last item button-enabled states.
- Verify auto-hide is suppressed while either button is hovered.
- Verify button actions call the previous and next callbacks.
- Run the complete unit test suite and production app build.
