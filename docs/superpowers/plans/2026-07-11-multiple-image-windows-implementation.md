# Multiple Image Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support independent image windows, reuse only the initial empty window for the first image, route menus to the active image window, and terminate when the final image window closes.

**Architecture:** `MainWindowController` exposes narrow lifecycle callbacks and records whether an open request has been assigned. `AppDelegate` owns an ordered collection of live image controllers, centralizes every URL source in `openURLs(_:)`, tracks the active controller for menu routing, and uses injected factory/termination seams for tests.

**Tech Stack:** Swift 6, AppKit, SwiftPM, XCTest, macOS 14+

## Global Constraints

- Keep the existing SwiftPM package and macOS 14 minimum deployment target.
- Continue development directly on `main` as previously authorized.
- Launch with exactly one empty image window.
- Reuse that empty startup window for only the first assigned URL; every subsequent URL receives a new image window.
- Preserve the full order of URL arrays delivered before or after launch.
- Keep every window's viewer, navigation, transform, edit, and unsaved state independent.
- Terminate exactly once when the final image window actually closes, even if Settings is visible.
- Route image/viewer menu actions to the key image window, or the most recently active live image window while Settings is key.
- Do not migrate to `NSDocument`, add tabs, restore sessions, or consolidate Quit prompts.

---

## File Structure

- Modify `Sources/ImageViewApp/MainWindowController.swift`: assigned-open state and key/close lifecycle callbacks.
- Modify `Sources/ImageViewApp/AppDelegate.swift`: live controller collection, URL pipeline, active-window menu routing, and termination seam.
- Modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`: lifecycle and assigned-open tests.
- Modify `Tests/ImageViewAppTests/AppDelegateTests.swift`: launch, multi-URL, close, termination, recent-items callback, and menu-routing tests.

---

### Task 1: Expose Image-Window Lifecycle and Assignment State

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes: existing `MainWindowController.open(url:)` and `NSWindowDelegate` callbacks.
- Produces: `private(set) var hasAssignedOpenRequest: Bool`, `var onWindowDidBecomeKey: ((MainWindowController) -> Void)?`, and `var onWindowDidClose: ((MainWindowController) -> Void)?`.

- [ ] **Step 1: Write failing assignment and lifecycle tests**

Add tests that construct a controller without presenting a visible production window:

```swift
func testOpenRequestMarksWindowAssignedBeforeDecodeCompletes() {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    XCTAssertFalse(controller.hasAssignedOpenRequest)

    controller.open(url: URL(fileURLWithPath: "/missing/image.png"))

    XCTAssertTrue(controller.hasAssignedOpenRequest)
}

func testWindowLifecycleCallbacksIdentifyTheirController() throws {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    var keyController: MainWindowController?
    var closedController: MainWindowController?
    controller.onWindowDidBecomeKey = { keyController = $0 }
    controller.onWindowDidClose = { closedController = $0 }
    let window = try XCTUnwrap(controller.window)

    controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

    XCTAssertTrue(keyController === controller)
    XCTAssertTrue(closedController === controller)
}
```

Reuse or add the existing isolated `UserDefaults` helper in `MainWindowControllerTests`.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'MainWindowControllerTests.testOpenRequestMarksWindowAssignedBeforeDecodeCompletes|MainWindowControllerTests.testWindowLifecycleCallbacksIdentifyTheirController'
```

Expected: compilation fails because the three lifecycle/assignment interfaces do not exist.

- [ ] **Step 3: Implement minimal controller state and callbacks**

Add module-internal interfaces near the existing controller callbacks:

```swift
private(set) var hasAssignedOpenRequest = false
var onWindowDidBecomeKey: ((MainWindowController) -> Void)?
var onWindowDidClose: ((MainWindowController) -> Void)?
```

Set assignment synchronously at the first line of `open(url:)`:

```swift
func open(url: URL) {
    hasAssignedOpenRequest = true
    // Existing open implementation remains unchanged below this line.
}
```

Extend the existing delegate methods without replacing their current refresh behavior:

```swift
func windowDidBecomeKey(_ notification: Notification) {
    onWindowDidBecomeKey?(self)
    guard Self.shouldRefreshCurrentFileOnWindowActivation() else { return }
    refreshCurrentFileForExternalChanges()
    startExternalFileCheckTimer()
}

func windowWillClose(_ notification: Notification) {
    externalFileCheckTimer?.invalidate()
    externalFileCheckTimer = nil
    onWindowDidClose?(self)
}
```

`windowShouldClose(_:)` remains the authority for unsaved-change cancellation. `windowWillClose` runs only after AppKit accepts the close.

- [ ] **Step 4: Run focused and complete controller tests**

Run the Step 2 command, then:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter MainWindowControllerTests
```

Expected: both new tests and all existing controller tests pass with zero failures.

- [ ] **Step 5: Commit controller lifecycle support**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift
git commit -m "feat: expose image window lifecycle"
```

---

### Task 2: Manage Multiple Controllers and Unified URL Opening

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Modify: `Tests/ImageViewAppTests/AppDelegateTests.swift`

**Interfaces:**
- Consumes: Task 1's `hasAssignedOpenRequest`, `onWindowDidBecomeKey`, and `onWindowDidClose`.
- Produces: `AppDelegate.openURLs(_:)`, live image-controller ownership, pending URL accumulation, active controller selection, and injected `makeImageWindowController`/`showImageWindow`/`openImageURL`/`terminateApplication` closures.

- [ ] **Step 1: Add failing tests for startup reuse and multi-URL creation**

Use real controllers created through an injected factory. The harness supplies a no-op `showImageWindow` closure and an `openImageURL` closure that records the URL and then calls `controller.open(url:)`, preserving the real synchronous assignment behavior without presenting windows. Add a module-internal test surface to `AppDelegate`: `imageWindowCount`, `imageWindowControllersForTesting`, `pendingURLsForTesting`, and `activeImageWindowControllerForTesting`.

```swift
func testLaunchCreatesOneEmptyImageWindow() {
    let harness = WindowHarness()
    let delegate = harness.makeDelegate()

    delegate.finishLaunchingForTesting()

    XCTAssertEqual(delegate.imageWindowCount, 1)
    XCTAssertFalse(delegate.imageWindowControllersForTesting[0].hasAssignedOpenRequest)
}

func testFirstURLReusesEmptyWindowAndLaterURLsCreateWindows() {
    let harness = WindowHarness()
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()
    let urls = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")]

    delegate.openURLs(urls)

    XCTAssertEqual(delegate.imageWindowCount, 2)
    XCTAssertEqual(harness.openRequests, urls)
    XCTAssertTrue(delegate.imageWindowControllersForTesting[0].hasAssignedOpenRequest)
    XCTAssertFalse(delegate.imageWindowControllersForTesting[0] === delegate.imageWindowControllersForTesting[1])
}

func testPrelaunchURLsAreAccumulatedAndOpenedInOrder() {
    let harness = WindowHarness()
    let delegate = harness.makeDelegate()
    let first = URL(fileURLWithPath: "/first.png")
    let second = URL(fileURLWithPath: "/second.png")

    delegate.application(NSApplication.shared, open: [first, second])
    XCTAssertEqual(delegate.pendingURLsForTesting, [first, second])

    delegate.finishLaunchingForTesting()

    XCTAssertEqual(harness.openRequests, [first, second])
    XCTAssertEqual(delegate.imageWindowCount, 2)
}
```

`finishLaunchingForTesting()` performs the lifecycle work of `applicationDidFinishLaunching` without activating `NSApp`; production `applicationDidFinishLaunching` calls the same private helper and then activates the app.

- [ ] **Step 2: Add failing tests for close and termination semantics**

```swift
func testClosingOneWindowKeepsOthersAndClosingFinalWindowTerminatesOnce() {
    let harness = WindowHarness()
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()
    delegate.openURLs([URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")])
    let controllers = delegate.imageWindowControllersForTesting

    delegate.imageWindowDidClose(controllers[0])
    XCTAssertEqual(delegate.imageWindowCount, 1)
    XCTAssertEqual(harness.terminationCount, 0)

    delegate.imageWindowDidClose(controllers[1])
    delegate.imageWindowDidClose(controllers[1])

    XCTAssertEqual(delegate.imageWindowCount, 0)
    XCTAssertEqual(harness.terminationCount, 1)
}
```

Add a test that creates/shows the Settings controller through an injected or test helper path, closes the final image controller, and still expects one termination request.

- [ ] **Step 3: Add failing tests for active-window menu routing**

```swift
func testMenuTargetsFollowKeyAndMostRecentlyActiveImageWindow() throws {
    let harness = WindowHarness()
    let delegate = harness.makeDelegate()
    let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
    delegate.finishLaunchingForTesting(installMenu: false)
    delegate.openURLs([URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")])
    let first = delegate.imageWindowControllersForTesting[0]
    let second = delegate.imageWindowControllersForTesting[1]

    delegate.imageWindowDidBecomeKey(first)
    XCTAssertTrue(menu.items[2].submenu?.item(withTitle: "Next Image")?.target === first)

    delegate.imageWindowDidBecomeKey(second)
    XCTAssertTrue(menu.items[2].submenu?.item(withTitle: "Next Image")?.target === second)

    delegate.connectMenuTargetsForTesting()
    XCTAssertTrue(delegate.activeImageWindowControllerForTesting === second)
}
```

The Settings-key case invokes `connectMenuTargetsForTesting()` without changing the active image controller and asserts the second controller remains the target.

- [ ] **Step 4: Run AppDelegate tests and verify RED**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter AppDelegateTests
```

Expected: compilation fails because the multi-window initializer seams, URL pipeline, lifecycle hooks, and test surfaces do not exist.

- [ ] **Step 5: Implement injected ownership and lifecycle seams**

Replace the single controller and pending URL with:

```swift
private var imageWindowControllers: [MainWindowController] = []
private weak var activeImageWindowController: MainWindowController?
private var pendingLaunchURLs: [URL] = []
private var didRequestTermination = false
private let makeImageWindowController: (AppSettings) -> MainWindowController
private let showImageWindow: (MainWindowController) -> Void
private let openImageURL: (MainWindowController, URL) -> Void
private let terminateApplication: () -> Void

init(
    settings: AppSettings = .shared,
    defaultApplicationService: DefaultApplicationServicing = WorkspaceDefaultApplicationService(),
    makeImageWindowController: @escaping (AppSettings) -> MainWindowController = { MainWindowController(settings: $0) },
    showImageWindow: @escaping (MainWindowController) -> Void = { $0.showWindow(nil) },
    openImageURL: @escaping (MainWindowController, URL) -> Void = { $0.open(url: $1) },
    terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) }
) {
    self.settings = settings
    self.defaultApplicationService = defaultApplicationService
    self.makeImageWindowController = makeImageWindowController
    self.showImageWindow = showImageWindow
    self.openImageURL = openImageURL
    self.terminateApplication = terminateApplication
    super.init()
}
```

Implement controller creation and callbacks:

```swift
@discardableResult
private func createImageWindow() -> MainWindowController {
    let controller = makeImageWindowController(settings)
    controller.onSuccessfulOpen = { [weak self] url in
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        self?.rebuildOpenRecentMenu()
    }
    controller.onWindowDidBecomeKey = { [weak self] controller in
        self?.imageWindowDidBecomeKey(controller)
    }
    controller.onWindowDidClose = { [weak self] controller in
        self?.imageWindowDidClose(controller)
    }
    imageWindowControllers.append(controller)
    activeImageWindowController = controller
    showImageWindow(controller)
    return controller
}

func imageWindowDidBecomeKey(_ controller: MainWindowController) {
    guard imageWindowControllers.contains(where: { $0 === controller }) else { return }
    activeImageWindowController = controller
    connectMenuTargets()
}

func imageWindowDidClose(_ controller: MainWindowController) {
    guard let index = imageWindowControllers.firstIndex(where: { $0 === controller }) else { return }
    imageWindowControllers.remove(at: index)
    if activeImageWindowController === controller {
        activeImageWindowController = imageWindowControllers.last
    }
    connectMenuTargets()
    guard imageWindowControllers.isEmpty, !didRequestTermination else { return }
    didRequestTermination = true
    terminateApplication()
}
```

- [ ] **Step 6: Implement the shared ordered URL pipeline**

```swift
func openURLs(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    for url in urls {
        let controller: MainWindowController
        if let empty = imageWindowControllers.first(where: { !$0.hasAssignedOpenRequest }) {
            controller = empty
        } else {
            controller = createImageWindow()
        }
        activeImageWindowController = controller
        openImageURL(controller, url)
        showImageWindow(controller)
    }
    connectMenuTargets()
}
```

Change prelaunch handling to append the full array:

```swift
func application(_ application: NSApplication, open urls: [URL]) {
    guard didFinishLaunching else {
        pendingLaunchURLs.append(contentsOf: urls)
        return
    }
    openURLs(urls)
}
```

The shared finish helper creates exactly one startup controller, installs menus when requested, drains `pendingLaunchURLs` in order, and clears the queue. Update `openImage(_:)` to allow multiple selection and call `openURLs(panel.urls)`. Update `openRecentImage(_:)` to call `openURLs([url])`.

- [ ] **Step 7: Route menus to the active live image controller**

Implement:

```swift
private var menuTargetImageController: MainWindowController? {
    if let keyWindow = NSApp.keyWindow,
       let keyController = imageWindowControllers.first(where: { $0.window === keyWindow }) {
        return keyController
    }
    if let activeImageWindowController,
       imageWindowControllers.contains(where: { $0 === activeImageWindowController }) {
        return activeImageWindowController
    }
    return imageWindowControllers.last
}
```

Change `connectMenuTargets()` to use `menuTargetImageController`. Change `connectControllerActions(in:target:)` so a nil target clears matching controller-action targets rather than leaving a closed controller attached:

```swift
private func connectControllerActions(in menu: NSMenu?, target: MainWindowController?) {
    guard let menu else { return }
    for item in menu.items {
        if let action = item.action,
           MainWindowController.menuCommand(for: action) != nil ||
           action == #selector(MainWindowController.toggleFilmstrip(_:)) ||
           action == #selector(MainWindowController.toggleInspector(_:)) {
            item.target = target
        }
        connectControllerActions(in: item.submenu, target: target)
    }
}
```

Preserve app-owned targets such as Open, Settings, appearance, Help, and Quit.

- [ ] **Step 8: Run focused and full verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'AppDelegateTests|MainWindowControllerTests'
```

Expected: all multi-window and existing controller/delegate tests pass with zero failures.

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox
```

Expected: the complete suite passes with zero failures.

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh
```

Expected: Release build succeeds and produces `/Users/gaoyinrui/Documents/Codex/ImageView/.build/ImageView.app`.

- [ ] **Step 9: Manual smoke test without modifying file associations**

Launch `.build/ImageView.app` and verify:

1. One empty image window appears.
2. Open two images together; the first fills the empty window and the second creates a new window.
3. Switch windows and verify View/Image commands affect only the key window.
4. Open Settings, then close one image window; the other remains usable.
5. Close the final image window; ImageView and Settings both exit.

- [ ] **Step 10: Commit multi-window management**

```bash
git add Sources/ImageViewApp/AppDelegate.swift Tests/ImageViewAppTests/AppDelegateTests.swift
git commit -m "feat: support multiple image windows"
```

---

## Completion Checklist

- [ ] One empty image window appears at launch.
- [ ] The first URL reuses only that empty window.
- [ ] Every later or batched URL gets an independent controller.
- [ ] Prelaunch URLs retain order and duplicates.
- [ ] Menu commands follow the key or most recently active image window.
- [ ] Closing one image window preserves others.
- [ ] Closing the final image window requests termination once, regardless of Settings.
- [ ] Recent items update from successful opens in every window.
- [ ] Full Swift tests and Release build pass.
