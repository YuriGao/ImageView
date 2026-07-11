# Centered Filmstrip Selection Design

## Goal

Keep the selected image thumbnail exactly centered in the filmstrip viewport whenever the selection or viewport size changes.

## Behavior

- The selected thumbnail is centered for middle, first, and last items.
- First and last items use empty space on the missing side; thumbnails do not wrap or repeat.
- Changing images recenters after thumbnail sizes update.
- Resizing the image window or filmstrip recenters the current item.
- Clicking a thumbnail continues to select that item normally.
- An empty list, nil selection, or selection absent from the list resets the filmstrip to its leading position without inventing a selection.
- Scrollbars remain hidden and the current filmstrip appearance is preserved.

## Layout

`FilmstripView` keeps transparent leading and trailing spacer views inside its horizontal stack. Their width is:

`max(0, (viewport width - selected thumbnail width) / 2)`

The selected button is laid out between those spacers with the existing thumbnail sizes and spacing. After layout, the scroll origin is set so the selected button's midpoint matches the clip view's horizontal midpoint.

The spacers expand the document width enough for the first and last buttons to reach the viewport center without elastic overscroll. They do not accept clicks or affect thumbnail appearance.

## State and Lifecycle

`FilmstripView` stores the current selected item and selected button reference. `apply(items:current:)` rebuilds content, updates spacer widths after the viewport has a valid size, and centers the selection. `layout()` detects viewport-width changes, updates spacers, and recenters without rebuilding thumbnails.

A reentrancy guard prevents the frame and scroll updates performed during layout from recursively triggering another centering pass.

## Testing

Tests verify:

- The middle selected thumbnail center matches the viewport center.
- The first selected thumbnail centers with leading empty space.
- The last selected thumbnail centers with trailing empty space.
- Resizing the filmstrip recomputes spacer widths and preserves centering.
- Nil or absent selection returns to the leading scroll position.
- Existing selection callbacks and thumbnail sizing remain unchanged.

Final verification runs the complete Swift test suite and the Release application build script.

## Out of Scope

- Circular thumbnail wrapping.
- Animated scrolling between selections.
- User-configurable alignment.
- Changes to filmstrip visibility timing or thumbnail dimensions.
