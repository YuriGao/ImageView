# Appearance Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent, application-wide System/Light/Dark appearance selector to the localized View menu.

**Architecture:** `AppSettings` owns a persisted `AppAppearance` enum as the single source of truth. `AppDelegate` maps that value to `NSApplication.appearance`, owns three localized menu actions, and derives mutually exclusive checkmarks from the setting.

**Tech Stack:** Swift 6, AppKit, Combine, XCTest, Swift Package Manager

## Global Constraints

- The menu hierarchy is **View → Appearance** in English and **显示 → 外观** in Simplified Chinese.
- The choices are **System**, **Light**, and **Dark**; `system` is the default and fallback.
- Selection applies immediately to the whole application and persists across launches.
- Existing views continue to use effective-appearance callbacks; do not add per-view theme state.
- Do not add keyboard shortcuts, Settings-window controls, custom themes, accent colors, or per-window appearance.

---

### Task 1: Persist the Appearance Selection

**Files:**
- Modify: `Sources/ImageViewApp/Settings/AppSettings.swift`
- Modify: `Tests/ImageViewAppTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `enum AppAppearance: String, CaseIterable { case system, light, dark }`
- Produces: `AppSettings.appearance: AppAppearance`

- [ ] **Step 1: Write failing settings tests**

Add tests that assert the default, persistence, and invalid-value fallback:

```swift
func testAppearanceDefaultsToSystem() {
    XCTAssertEqual(AppSettings(defaults: makeIsolatedDefaults()).appearance, .system)
}

func testAppearancePersistsAcrossInstances() {
    let defaults = makeIsolatedDefaults()
    AppSettings(defaults: defaults).appearance = .dark
    XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
}

func testUnknownAppearanceFallsBackToSystem() {
    let defaults = makeIsolatedDefaults()
    defaults.set("sepia", forKey: "appearance")
    XCTAssertEqual(AppSettings(defaults: defaults).appearance, .system)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter AppSettingsTests --disable-sandbox`

Expected: compilation fails because `AppSettings.appearance` and `AppAppearance` do not exist.

- [ ] **Step 3: Add the persisted appearance model**

Add the enum and published property:

```swift
enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

@Published var appearance: AppAppearance {
    didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
}
```

Initialize it with:

```swift
appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
```

Add `static let appearanceKey = "appearance"` beside the existing keys.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `swift test --filter AppSettingsTests --disable-sandbox`

Expected: all `AppSettingsTests` pass with zero failures.

- [ ] **Step 5: Commit the settings model**

```bash
git add Sources/ImageViewApp/Settings/AppSettings.swift Tests/ImageViewAppTests/AppSettingsTests.swift
git commit -m "feat: persist application appearance"
```

---

### Task 2: Add and Apply the Localized Appearance Menu

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ImageViewAppTests/AppDelegateTests.swift`
- Modify: `Tests/ImageViewAppTests/AppStringsTests.swift`

**Interfaces:**
- Consumes: `AppSettings.appearance: AppAppearance`
- Produces: `AppDelegate.applyAppearance()` and the `selectSystemAppearance:`, `selectLightAppearance:`, and `selectDarkAppearance:` menu actions.

- [ ] **Step 1: Write failing localization and menu tests**

Extend string coverage to include `menu.view.appearance`, `.system`, `.light`, and `.dark`. Add `AppDelegateTests` that construct the delegate with isolated settings and assert:

```swift
let appearanceMenu = menu.items[2].submenu?
    .item(withTitle: "Appearance")?.submenu
XCTAssertEqual(appearanceMenu?.items.map(\.title), ["System", "Light", "Dark"])
XCTAssertEqual(appearanceMenu?.items.map(\.state), [.on, .off, .off])
```

Add a mapping test using a dedicated `NSApplication`-appearance setter surface so `.system` produces `nil`, `.light` produces `.aqua`, and `.dark` produces `.darkAqua`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter AppDelegateTests --disable-sandbox`

Expected: tests fail because the localized submenu and appearance application API do not exist.

- [ ] **Step 3: Add localization keys**

Append these keys to `AppStrings.menuKeys` and both string tables:

```text
menu.view.appearance
menu.view.appearance.system
menu.view.appearance.light
menu.view.appearance.dark
```

English values are `Appearance`, `System`, `Light`, and `Dark`. Simplified Chinese values are `外观`, `跟随系统`, `浅色`, and `深色`.

- [ ] **Step 4: Add the app-wide appearance mapping**

Allow test injection with `init(settings: AppSettings = .shared)` and store the supplied settings. Implement:

```swift
func applyAppearance(to application: NSApplication = NSApp) {
    switch settings.appearance {
    case .system: application.appearance = nil
    case .light: application.appearance = NSAppearance(named: .aqua)
    case .dark: application.appearance = NSAppearance(named: .darkAqua)
    }
}
```

Call it at the start of `applicationDidFinishLaunching`, before `showWindowIfNeeded()`.

- [ ] **Step 5: Build the submenu and actions**

Create an Appearance submenu after the filmstrip and inspector controls. Each item targets `AppDelegate`, has no shortcut, and uses one selector:

```swift
@objc private func selectSystemAppearance(_ sender: Any?) { selectAppearance(.system) }
@objc private func selectLightAppearance(_ sender: Any?) { selectAppearance(.light) }
@objc private func selectDarkAppearance(_ sender: Any?) { selectAppearance(.dark) }
```

`selectAppearance(_:)` updates `settings.appearance`, calls `applyAppearance()`, and calls `updateAppearanceMenuState()`. That state method marks exactly the item whose represented `AppAppearance` equals the current setting as `.on` and the other two as `.off`. Call it after menu construction.

- [ ] **Step 6: Run focused and complete tests**

Run: `swift test --filter 'AppDelegateTests|AppStringsTests' --disable-sandbox`

Expected: all appearance menu and localization tests pass with zero failures.

Run: `swift test --disable-sandbox`

Expected: the complete project test suite passes with zero failures.

- [ ] **Step 7: Build, inspect, and commit**

Run: `scripts/build-app.sh`

Expected: the Release app bundle is produced successfully.

Run: `git diff --check`

Expected: no output.

```bash
git add Sources/ImageViewApp/AppDelegate.swift Sources/ImageViewApp/Localization/AppStrings.swift Sources/ImageViewApp/Resources/en.lproj/Localizable.strings Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings Tests/ImageViewAppTests/AppDelegateTests.swift Tests/ImageViewAppTests/AppStringsTests.swift docs/superpowers/plans/2026-07-11-appearance-menu-implementation.md
git commit -m "feat: add application appearance menu"
```
