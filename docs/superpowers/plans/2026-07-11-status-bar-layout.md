# Status Bar Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the bottom status bar into left-aligned pixel dimensions, centered page position, and right-aligned zoom information beside the inspector button.

**Architecture:** Keep all status-bar presentation in `MainWindowController`. Replace the combined status label with three labels and split formatting into pure static helpers so metadata, navigation, and zoom updates remain independent and directly testable.

**Tech Stack:** Swift 6, AppKit, Combine, XCTest, Swift Package Manager

## Global Constraints

- Keep the existing 28-point bottom status-bar height.
- Left text uses `6000 × 4000 px`; empty state uses `— × — px`.
- Center text uses `18 / 191`; empty state uses `0 / 0`.
- Right text uses `100%` and remains immediately before the information button.
- Page text is centered against the full status bar.
- Dimension text compresses before page or zoom text in narrow windows.
- Preserve the existing font, weight, secondary label color, divider, and information button.

---

### Task 1: Split and Reposition Status Information

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

**Interfaces:**
- Consumes: `ImageMetadata.pixelWidth`, `ImageMetadata.pixelHeight`, `NavigationState.currentIndex`, `NavigationState.items`, and `ImageCanvasView.scale`.
- Produces: `dimensionText(pixelWidth:pixelHeight:)`, `pageText(navigationState:)`, and `zoomText(zoomScale:)`.

- [ ] **Step 1: Write failing formatting tests**

```swift
func testStatusBarFormatsDimensionsPageAndZoomIndependently() {
    let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
    let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
    let state = NavigationState(items: [first, second], currentURL: second.url)

    XCTAssertEqual(MainWindowController.dimensionText(pixelWidth: 6000, pixelHeight: 4000), "6000 × 4000 px")
    XCTAssertEqual(MainWindowController.dimensionText(pixelWidth: nil, pixelHeight: nil), "— × — px")
    XCTAssertEqual(MainWindowController.pageText(navigationState: state), "2 / 2")
    XCTAssertEqual(MainWindowController.pageText(navigationState: nil), "0 / 0")
    XCTAssertEqual(MainWindowController.zoomText(zoomScale: 1.25), "125%")
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter MainWindowControllerTests/testStatusBarFormatsDimensionsPageAndZoomIndependently --disable-sandbox`

Expected: compilation fails because the three formatting helpers do not exist.

- [ ] **Step 3: Add the pure formatting helpers**

```swift
static func dimensionText(pixelWidth: Int?, pixelHeight: Int?) -> String {
    guard let pixelWidth, let pixelHeight else { return "— × — px" }
    return "\(pixelWidth) × \(pixelHeight) px"
}

static func pageText(navigationState: NavigationState?) -> String {
    guard let navigationState, let currentIndex = navigationState.currentIndex else { return "0 / 0" }
    return "\(currentIndex + 1) / \(navigationState.items.count)"
}

static func zoomText(zoomScale: CGFloat) -> String {
    "\(Int((zoomScale * 100).rounded()))%"
}
```

- [ ] **Step 4: Replace the combined label with three labels**

```swift
private let bottomDimensionLabel = NSTextField(labelWithString: "— × — px")
private let bottomPageLabel = NSTextField(labelWithString: "0 / 0")
private let bottomZoomLabel = NSTextField(labelWithString: "100%")
```

Add all three labels to `bottomBarView`. Pin dimensions to the 12-point leading inset, page to `bottomBarView.centerXAnchor`, zoom to the information button with the existing 8-point spacing, and vertically center all labels. Add non-overlap inequalities around the page label. Set lower horizontal compression resistance on the dimension label than on the page and zoom labels.

- [ ] **Step 5: Connect independent data updates**

```swift
private func updatePageStatus(navigationState: NavigationState?) {
    bottomPageLabel.stringValue = Self.pageText(navigationState: navigationState)
}

private func updateZoomStatus(zoomScale: CGFloat? = nil) {
    bottomZoomLabel.stringValue = Self.zoomText(zoomScale: zoomScale ?? canvas.scale)
}

private func updateDimensionStatus(metadata: ImageMetadata?) {
    bottomDimensionLabel.stringValue = Self.dimensionText(
        pixelWidth: metadata?.pixelWidth,
        pixelHeight: metadata?.pixelHeight
    )
}
```

Call `updateDimensionStatus` from the existing metadata sink, `updatePageStatus` from the navigation-state sink, and `updateZoomStatus` from canvas transform changes and initial setup. Remove the obsolete combined `statusText` and `bottomStatusLabel` code.

- [ ] **Step 6: Run focused and complete tests**

Run: `swift test --filter MainWindowControllerTests --disable-sandbox`

Expected: all `MainWindowControllerTests` pass with zero failures.

Run: `swift test --disable-sandbox`

Expected: all project tests pass with zero failures.

- [ ] **Step 7: Build and commit**

Run: `scripts/build-app.sh`

Expected: `.build/ImageView.app` is produced successfully.

```bash
git add Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift docs/superpowers/plans/2026-07-11-status-bar-layout.md
git commit -m "feat: reorganize status bar information"
```
