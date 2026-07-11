# Unified Overlay Auto-Hide Design

## Goal

Make the floating previous/next page controls and filmstrip overlay disappear on the same schedule after pointer activity.

## Root Cause

Both overlays already use the same interaction pattern: pointer movement reveals them and restarts a timer, hovering cancels that overlay's timer, and leaving restarts it. Their timing differs because `MainWindowController` defines separate values: the filmstrip waits 1.8 seconds and fades for 0.18 seconds, while the page controls wait 1.5 seconds and fade for 0.16 seconds.

## Behavior

- Pointer activity reveals every eligible overlay and starts its auto-hide countdown.
- Both overlays wait 1.8 seconds before fading.
- Both overlays use a 0.18-second fade-out animation.
- Hovering an overlay cancels only that overlay's countdown.
- Leaving an overlay restarts its full 1.8-second countdown.
- Existing eligibility rules remain unchanged: the filmstrip still depends on its setting, a loaded image, fit scale, and pointer activity; page controls still require multiple images and no crop session.
- Existing reveal animation durations remain unchanged because the reported inconsistency concerns disappearance timing.

## Architecture

Replace the separate filmstrip and page-control auto-hide delay constants with one shared `overlayAutoHideDelay`. Add one shared `overlayFadeOutDuration`. Both scheduling methods and both non-immediate hide methods consume these constants.

Keep the two timers, generation tokens, and hover states independent. This preserves the current behavior where hovering one overlay does not hold the other visible.

## Testing

Add a focused test asserting that the shared delay is 1.8 seconds and the shared fade-out duration is 0.18 seconds. Removing the two component-specific delay constants makes timing divergence a compile-time structural regression rather than only a visual regression.

Run the focused `MainWindowControllerTests`, the complete SwiftPM test suite, and the production app build.

## Out of Scope

- Merging the two timers or visibility state machines.
- Changing reveal animation durations.
- Changing overlay eligibility, layout, or hover behavior.
- Adding a user-configurable timeout.
