# Native Menu and Localization Design

## Goal

Remove the floating HUD and image-tools toolbar. Move their commands into a complete native macOS menu bar whose labels follow the system language.

## Menu Structure

The application menu provides Settings and Quit. The remaining menus are:

- File: Open, Open Recent, Close, Rename, Reveal in Finder, Copy Path, and Move to Trash.
- View: Previous Image, Next Image, Actual Size, Zoom to Fit, Filmstrip, Info, and Full Screen.
- Image: Rotate Clockwise, Rotate Counterclockwise, Flip Horizontal, Flip Vertical, Crop, Save Edits, Save As, and Discard Edits.
- Window: Minimize, Zoom, and Bring All to Front.
- Help: ImageView Help.

All image and file actions target `MainWindowController`, so menu, keyboard, and existing image commands execute the same code paths. Menu validation reflects image availability, edit state, and toggled View options.

## Localization

Use `Localizable.strings` resources for English and Simplified Chinese. `Bundle` chooses the preferred macOS localization; unsupported languages use English. Menu construction and existing app-facing strings obtain labels through a small app-localized-string helper rather than hard-coded presentation text. Keyboard equivalents remain independent of labels.

## HUD Removal

Remove `HUDView`, `ImageToolsToolbarView`, HUD hover tracking, temporary visibility timers, and the Pin HUD preference. The title bar, canvas, crop controls, inspector, filmstrip, and bottom status bar remain. The canvas no longer reserves space for the removed overlays.

## Verification

Tests cover the menu hierarchy and labels for English and Simplified Chinese, action routing and enabled state, and the absence of HUD-dependent layout/visibility behavior. The full Swift test suite and app packaging build must pass.
