# Status Bar Layout Design

## Goal

Reorganize the bottom status bar into stable left, center, and right information regions so image dimensions, page position, zoom, and the inspector control remain easy to scan.

## Layout

- Left: image pixel dimensions in `6000 × 4000 px` format.
- Center: page position in `18 / 191` format, centered against the full status bar rather than the remaining free space.
- Right: zoom percentage in `100%` format, followed by the existing information button.
- Keep the existing 28-point status-bar height, font size, font weight, secondary label color, divider, and information button.
- Use three independent `NSTextField` labels rather than spacing inside one combined string.

## Constraint Priorities

- Pin the dimension label to the left inset.
- Pin the page label to the exact horizontal center of the status bar.
- Pin the zoom label immediately before the information button with the existing compact spacing.
- Prevent the left and right labels from crossing into the centered page label.
- Give the page and zoom labels higher horizontal compression resistance than the dimension label so narrow windows truncate the left label first.

## Data and Empty States

- Pixel dimensions come from `ViewerViewModel.currentMetadata` and update after image loading, navigation, edits, external reloads, or clearing the current image.
- Page position comes from `NavigationState`.
- Zoom percentage comes from `ImageCanvasView.scale` and updates on canvas transform changes.
- With no image, show `— × — px`, `0 / 0`, and `100%`.

## Testing

- Verify dimension, page, and zoom formatting independently.
- Verify metadata absence produces the approved dimension placeholder.
- Verify navigation updates do not alter zoom formatting and transform updates do not alter page formatting.
- Run the complete unit test suite and production app build.
