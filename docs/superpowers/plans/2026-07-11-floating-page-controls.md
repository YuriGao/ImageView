# Floating Page Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add clickable, appearance-adaptive previous and next buttons that transiently float at the horizontal edges of the image canvas.

**Architecture:** A new `PageNavigationOverlayView` owns the two AppKit buttons, appearance, hover tracking, and click callbacks. `MainWindowController` embeds the view over the canvas, derives enabled states from `NavigationState`, and owns reveal and auto-hide timing because it already coordinates pointer movement, navigation, and crop mode.

**Tech Stack:** Swift 6, AppKit, Combine, XCTest, Swift Package Manager

## Global Constraints

- Each control is 44 x 64 points and vertically centered in the canvas.
- Symbols are `chevron.left` and `chevron.right`.
- Background follows system appearance; border uses `separatorColor` at one physical pixel.
- Controls reveal on pointer movement and successful navigation, then fade after 1.5 seconds.
- Hovering either control suppresses auto-hide.
- Hide controls with zero or one image and during crop editing.
- Disable the previous control at the first item and the next control at the last item.
- Preserve all existing title bar, status bar, filmstrip, canvas, and navigation behavior.

---

### Task 1: Build the Page Navigation Overlay View

**Files:**
- Create: `Sources/ImageViewApp/Viewer/PageNavigationOverlayView.swift`
- Create: `Tests/ImageViewAppTests/PageNavigationOverlayViewTests.swift`

**Interfaces:**
- Consumes: AppKit `NSButton`, `NSImage(systemSymbolName:accessibilityDescription:)`, and `NSTrackingArea`.
- Produces: `PageNavigationOverlayView.onPrevious`, `onNext`, `onPointerEntered`, `onPointerExited`, and `update(previousEnabled:nextEnabled:)`.

- [ ] **Step 1: Write failing view tests**

```swift
import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class PageNavigationOverlayViewTests: XCTestCase {
    func testControlsUseApprovedSymbolsAndDimensions() {
        let view = PageNavigationOverlayView()
        XCTAssertEqual(PageNavigationOverlayView.controlSize, CGSize(width: 44, height: 64))
        XCTAssertEqual(view.debugPreviousButton.image?.accessibilityDescription, "Previous Image")
        XCTAssertEqual(view.debugNextButton.image?.accessibilityDescription, "Next Image")
    }

    func testUpdateAppliesSequenceBoundaryStates() {
        let view = PageNavigationOverlayView()
        view.update(previousEnabled: false, nextEnabled: true)
        XCTAssertFalse(view.debugPreviousButton.isEnabled)
        XCTAssertTrue(view.debugNextButton.isEnabled)
    }

    func testButtonsCallNavigationCallbacks() {
        let view = PageNavigationOverlayView()
        var previousCount = 0
        var nextCount = 0
        view.onPrevious = { previousCount += 1 }
        view.onNext = { nextCount += 1 }
        view.performDebugPrevious()
        view.performDebugNext()
        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(nextCount, 1)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter PageNavigationOverlayViewTests --disable-sandbox`

Expected: compilation fails because `PageNavigationOverlayView` does not exist.

- [ ] **Step 3: Implement the focused AppKit view**

```swift
import AppKit

@MainActor
final class PageNavigationOverlayView: NSView {
    static let controlSize = CGSize(width: 44, height: 64)
    static var backgroundColor: NSColor { .windowBackgroundColor }
    static var borderColor: NSColor { .separatorColor }

    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private var pointerTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        configure(previousButton, symbol: "chevron.left", description: "Previous Image", action: #selector(showPrevious))
        configure(nextButton, symbol: "chevron.right", description: "Next Image", action: #selector(showNext))
        addSubview(previousButton)
        addSubview(nextButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(previousEnabled: Bool, nextEnabled: Bool) {
        previousButton.isEnabled = previousEnabled
        nextButton.isEnabled = nextEnabled
    }

    @objc private func showPrevious() { onPrevious?() }
    @objc private func showNext() { onNext?() }
}
```

Use this tracking and test-access implementation around the button configuration shown above:

```swift
override func updateTrackingAreas() {
    if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
    let area = NSTrackingArea(
        rect: .zero,
        options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
        owner: self
    )
    addTrackingArea(area)
    pointerTrackingArea = area
    super.updateTrackingAreas()
}

override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
override func mouseExited(with event: NSEvent) { onPointerExited?() }

#if DEBUG
var debugPreviousButton: NSButton { previousButton }
var debugNextButton: NSButton { nextButton }
func performDebugPrevious() { showPrevious() }
func performDebugNext() { showNext() }
#endif
```

Configure each button as borderless, set `wantsLayer = true`, assign a dynamic background and separator border in `updateLayer()`, and constrain the previous button to the leading edge and the next button to the trailing edge. Both buttons use `controlSize` and center vertically in the overlay.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter PageNavigationOverlayViewTests --disable-sandbox`

Expected: all `PageNavigationOverlayViewTests` pass with zero failures.

- [ ] **Step 5: Commit the isolated view**

```bash
git add Sources/ImageViewApp/Viewer/PageNavigationOverlayView.swift Tests/ImageViewAppTests/PageNavigationOverlayViewTests.swift
git commit -m "feat: add floating page control view"
```

### Task 2: Integrate Visibility and Navigation State

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes: `PageNavigationOverlayView.update(previousEnabled:nextEnabled:)` and its four callbacks.
- Produces: `MainWindowController.shouldDisplayPageControls(itemCount:isCropping:)`, `pageControlAvailability(navigationState:)`, and `shouldAutoHidePageControls(pointerIsOverControls:)`.

- [ ] **Step 1: Write failing controller state tests**

```swift
func testPageControlsRequireMultipleImagesAndNoCropSession() {
    XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 0, isCropping: false))
    XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 1, isCropping: false))
    XCTAssertTrue(MainWindowController.shouldDisplayPageControls(itemCount: 2, isCropping: false))
    XCTAssertFalse(MainWindowController.shouldDisplayPageControls(itemCount: 2, isCropping: true))
}

func testPageControlAvailabilityTracksSequenceBoundaries() {
    let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
    let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
    let firstState = NavigationState(items: [first, second], currentURL: first.url)
    let secondState = NavigationState(items: [first, second], currentURL: second.url)
    XCTAssertEqual(MainWindowController.pageControlAvailability(navigationState: firstState), .init(previous: false, next: true))
    XCTAssertEqual(MainWindowController.pageControlAvailability(navigationState: secondState), .init(previous: true, next: false))
}

func testPageControlsStayVisibleWhileHovered() {
    XCTAssertFalse(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: true))
    XCTAssertTrue(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: false))
}
```

- [ ] **Step 2: Run controller tests and verify RED**

Run: `swift test --filter MainWindowControllerTests --disable-sandbox`

Expected: compilation fails because the page-control state APIs do not exist.

- [ ] **Step 3: Add state helpers and integrate the overlay**

```swift
static let pageControlsAutoHideDelay: TimeInterval = 1.5

struct PageControlAvailability: Equatable {
    let previous: Bool
    let next: Bool
}

static func shouldDisplayPageControls(itemCount: Int, isCropping: Bool) -> Bool {
    itemCount > 1 && !isCropping
}

static func shouldAutoHidePageControls(pointerIsOverControls: Bool) -> Bool {
    !pointerIsOverControls
}
```

Add the integration state and callback wiring with these exact members:

```swift
private let pageNavigationOverlayView = PageNavigationOverlayView()
private var pageControlsHideTimer: Timer?
private var pageControlsVisibilityGeneration = 0
private var isPointerOverPageControls = false

rootView.onPointerMoved = { [weak self] in
    self?.revealFilmstripOverlay()
    self?.revealPageControls()
}
pageNavigationOverlayView.onPrevious = { [weak self] in self?.navigateToPreviousImage() }
pageNavigationOverlayView.onNext = { [weak self] in self?.navigateToNextImage() }
pageNavigationOverlayView.onPointerEntered = { [weak self] in
    self?.isPointerOverPageControls = true
    self?.cancelPageControlsAutoHide()
}
pageNavigationOverlayView.onPointerExited = { [weak self] in
    self?.isPointerOverPageControls = false
    self?.schedulePageControlsAutoHide()
}
```

Constrain the overlay to all four canvas edges. In the `viewModel.$navigationState` sink, call `pageControlAvailability(navigationState:)`, update both button states, reveal after a changed current index, and immediately hide when `shouldDisplayPageControls` is false. In `updateCropControls()`, immediately hide when `cropOverlay.isCropping` is true. Implement `revealPageControls`, `cancelPageControlsAutoHide`, `schedulePageControlsAutoHide`, and `hidePageControls` using the same generation-token pattern as the filmstrip, with `pageControlsAutoHideDelay` set to 1.5 seconds.

- [ ] **Step 4: Run controller and complete tests**

Run: `swift test --filter MainWindowControllerTests --disable-sandbox`

Expected: all controller tests pass with zero failures.

Run: `swift test --disable-sandbox`

Expected: all project tests pass with zero failures.

- [ ] **Step 5: Build the app**

Run: `scripts/build-app.sh`

Expected: `.build/ImageView.app` is produced successfully.

- [ ] **Step 6: Commit the integration**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift
git commit -m "feat: show floating page controls"
```
