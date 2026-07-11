# Appearance Menu Design

## Goal

Add an application-wide appearance selector to ImageView's native menu bar so users can choose whether the app follows macOS or always uses a light or dark appearance. The selected mode must take effect immediately and persist across launches.

## User Interface

Add an **Appearance** submenu to the existing **View** menu. In Simplified Chinese, the hierarchy is **显示 → 外观**.

The submenu contains three mutually exclusive items:

- **System** / **跟随系统**
- **Light** / **浅色**
- **Dark** / **深色**

The active item displays the standard macOS checkmark. No keyboard shortcuts are assigned because appearance changes are infrequent preferences and should not consume global menu shortcuts.

The initial selection is **System**, preserving the app's current behavior for existing users.

## Settings Model

Introduce an `AppAppearance` value with three cases: `system`, `light`, and `dark`. Store the selected value in `AppSettings` using `UserDefaults`.

If the persisted value is missing or invalid, use `system`. This makes the setting forward-compatible with corrupted or obsolete preference data without presenting an error to the user.

`AppSettings` remains the single source of truth. Menu actions update the setting, and menu state is derived from it.

## Appearance Application

Apply the selection to `NSApplication.appearance`:

- `system` sets the application appearance to `nil`, allowing macOS to supply the effective appearance.
- `light` sets the application appearance to `.aqua`.
- `dark` sets the application appearance to `.darkAqua`.

Apply the persisted setting during application launch before the main window is presented, avoiding a visible light-to-dark flash. Apply later menu changes immediately so existing windows, panels, menus, and newly created windows use the selected appearance.

Views that already respond to effective-appearance changes continue to use their existing AppKit callbacks; no per-view theme state is introduced.

## Menu Integration

`AppDelegate` owns the three appearance menu items and their actions because appearance is application-wide rather than tied to an image window. Each item targets the app delegate directly.

When the menu is built and whenever a selection changes, update all three item states so exactly one item is checked. Rebuilding the localized menu also derives its state from the persisted setting.

Add localization keys for the submenu and its three choices in English and Simplified Chinese.

## Error Handling

Appearance switching uses AppKit's built-in named appearances and has no expected runtime failure path. Unknown persisted values fall back to `system` and are treated as an unchecked invalid preference only during decoding; the visible menu always presents one valid checked selection.

## Testing

Add focused tests for:

- the default `system` value;
- persistence of each appearance selection;
- fallback from an unknown stored value;
- localized menu hierarchy and the three appearance choices;
- exactly one checked menu item matching the current setting;
- mapping each setting to the correct AppKit application appearance.

Run the complete SwiftPM test suite and the existing application bundle build script after implementation.

## Out of Scope

- A separate appearance control in the Settings window.
- Custom themes, accent colors, or per-window appearance.
- A two-state shortcut that bypasses the system-following option.
