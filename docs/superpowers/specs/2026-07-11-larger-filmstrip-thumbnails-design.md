# Larger Filmstrip Thumbnails Design

## Goal

Improve filmstrip readability by enlarging both regular and selected thumbnails while preserving the selected-item emphasis and keeping the overlay clear of the status bar.

## Approved Dimensions

- Regular thumbnail: 72 x 64 points.
- Selected thumbnail: 86 x 76 points.
- Filmstrip overlay height: 98 points.
- Keep the existing 6-point item spacing, 10-point content inset, corner radius, and border treatment.

## Behavior

The selected thumbnail remains larger than neighboring thumbnails. The overlay stays centered above the bottom of the image canvas and retains its existing reveal, hover, and auto-hide behavior.

## Testing

Unit tests verify the exact regular and selected thumbnail dimensions and the overlay height. The complete test suite and production app build must pass.
