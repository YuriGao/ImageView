# Centered Filmstrip Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the selected filmstrip thumbnail horizontally centered for every selection, including the first and last items, and preserve centering when the viewport resizes.

**Architecture:** `FilmstripView` adds transparent leading and trailing spacer views to its existing horizontal stack. It stores the selected button, recomputes spacer widths from the clip viewport, expands the document to its fitting size, and scrolls the selected button midpoint to the viewport midpoint after apply and layout-size changes.

**Tech Stack:** Swift 6, AppKit `NSScrollView`/`NSStackView`, SwiftPM, XCTest, macOS 14+

## Global Constraints

- Keep the existing SwiftPM package and macOS 14 minimum deployment target.
- Continue development directly on `main` as previously authorized.
- Center middle, first, and last selected thumbnails exactly.
- Use empty leading/trailing space for edge items; do not wrap or duplicate thumbnails.
- Recenter after selection changes and filmstrip viewport-width changes.
- Reset to the leading position for nil, missing, or empty selection.
- Preserve existing thumbnail sizes, spacing, click behavior, hidden scrollbars, and visibility timing.
- Do not add animated scrolling or user-configurable alignment.

---

### Task 1: Center the Selected Filmstrip Thumbnail

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/FilmstripView.swift`
- Modify: `Tests/ImageViewAppTests/FilmstripViewTests.swift`

**Interfaces:**
- Consumes: existing `FilmstripView.apply(items:current:)`, `contentView`, `stack`, and thumbnail sizes.
- Produces: dynamic edge spacers, `centerSelectedThumbnail()`, resize-aware `layout()`, and DEBUG-only geometry accessors.

- [ ] **Step 1: Write failing center-geometry tests**

Add reusable items and a viewport-center assertion:

```swift
private func makeItems(count: Int) -> [ImageItem] {
    (0..<count).map {
        ImageItem(url: URL(fileURLWithPath: "/tmp/\($0).png"), format: .png)
    }
}

private func assertSelectedThumbnailCentered(
    _ filmstrip: FilmstripView,
    accuracy: CGFloat = 0.5,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        filmstrip.debugSelectedCenterInViewport(),
        filmstrip.contentView.bounds.midX,
        accuracy: accuracy,
        file: file,
        line: line
    )
}
```

Add tests for a middle and both edge selections:

```swift
func testMiddleSelectionIsCenteredInViewport() {
    let items = makeItems(count: 7)
    let filmstrip = FilmstripView(frame: NSRect(x: 0, y: 0, width: 360, height: 78))

    filmstrip.apply(items: items, current: items[3])
    filmstrip.layoutSubtreeIfNeeded()

    assertSelectedThumbnailCentered(filmstrip)
}

func testFirstAndLastSelectionsUseEmptySpaceToRemainCentered() {
    let items = makeItems(count: 7)
    let filmstrip = FilmstripView(frame: NSRect(x: 0, y: 0, width: 360, height: 78))

    filmstrip.apply(items: items, current: items.first)
    filmstrip.layoutSubtreeIfNeeded()
    assertSelectedThumbnailCentered(filmstrip)
    XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), 0)

    filmstrip.apply(items: items, current: items.last)
    filmstrip.layoutSubtreeIfNeeded()
    assertSelectedThumbnailCentered(filmstrip)
    XCTAssertGreaterThan(filmstrip.debugTrailingSpacerWidth(), 0)
}
```

- [ ] **Step 2: Write failing resize and fallback tests**

```swift
func testViewportResizeRecomputesSpacersAndRecentersSelection() {
    let items = makeItems(count: 7)
    let filmstrip = FilmstripView(frame: NSRect(x: 0, y: 0, width: 300, height: 78))
    filmstrip.apply(items: items, current: items[3])
    filmstrip.layoutSubtreeIfNeeded()
    let originalSpacerWidth = filmstrip.debugLeadingSpacerWidth()

    filmstrip.frame.size.width = 460
    filmstrip.layoutSubtreeIfNeeded()

    assertSelectedThumbnailCentered(filmstrip)
    XCTAssertGreaterThan(filmstrip.debugLeadingSpacerWidth(), originalSpacerWidth)
}

func testNilOrMissingSelectionReturnsToLeadingPosition() {
    let items = makeItems(count: 5)
    let filmstrip = FilmstripView(frame: NSRect(x: 0, y: 0, width: 300, height: 78))
    filmstrip.apply(items: items, current: items[3])

    filmstrip.apply(items: items, current: nil)
    XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)

    let missing = ImageItem(url: URL(fileURLWithPath: "/tmp/missing.png"), format: .png)
    filmstrip.apply(items: items, current: missing)
    XCTAssertEqual(filmstrip.contentView.bounds.origin.x, 0, accuracy: 0.5)
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter FilmstripViewTests
```

Expected: compilation fails because the DEBUG geometry accessors do not exist; after adding declarations only, centering assertions fail because `apply` never adjusts scroll position.

- [ ] **Step 4: Add spacers and selection state**

Add properties:

```swift
private let leadingSpacer = NSView()
private let trailingSpacer = NSView()
private var leadingSpacerWidthConstraint: NSLayoutConstraint!
private var trailingSpacerWidthConstraint: NSLayoutConstraint!
private weak var selectedButton: FilmstripButton?
private var lastViewportWidth: CGFloat = -1
private var isUpdatingCenteredLayout = false
```

In `init()`, add the leading spacer as the first arranged view and create both width constraints with initial constant zero:

```swift
leadingSpacerWidthConstraint = leadingSpacer.widthAnchor.constraint(equalToConstant: 0)
trailingSpacerWidthConstraint = trailingSpacer.widthAnchor.constraint(equalToConstant: 0)
leadingSpacerWidthConstraint.isActive = true
trailingSpacerWidthConstraint.isActive = true
stack.addArrangedSubview(leadingSpacer)
stack.addArrangedSubview(trailingSpacer)
```

During `apply`, remove only thumbnail buttons and retain/reinsert the two spacers. The final arranged order must be:

1. `leadingSpacer`
2. All thumbnail buttons
3. `trailingSpacer`

Set `selectedButton` to the button whose item equals `current`. After building buttons call `updateCenteredLayout(force: true)`.

- [ ] **Step 5: Implement exact spacer and scroll calculations**

```swift
private func updateCenteredLayout(force: Bool = false) {
    guard !isUpdatingCenteredLayout else { return }
    let viewportWidth = contentView.bounds.width
    guard viewportWidth > 0 else { return }
    guard force || abs(viewportWidth - lastViewportWidth) > 0.5 else { return }

    isUpdatingCenteredLayout = true
    defer { isUpdatingCenteredLayout = false }
    lastViewportWidth = viewportWidth

    guard let selectedButton else {
        leadingSpacerWidthConstraint.constant = 0
        trailingSpacerWidthConstraint.constant = 0
        resizeDocumentToFit()
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
        return
    }

    selectedButton.layoutSubtreeIfNeeded()
    let spacerWidth = max(0, (viewportWidth - selectedButton.bounds.width) / 2)
    leadingSpacerWidthConstraint.constant = spacerWidth
    trailingSpacerWidthConstraint.constant = spacerWidth
    resizeDocumentToFit()
    centerSelectedThumbnail()
}

private func resizeDocumentToFit() {
    stack.layoutSubtreeIfNeeded()
    stack.frame.size = stack.fittingSize
}

private func centerSelectedThumbnail() {
    guard let selectedButton else { return }
    let selectedCenter = selectedButton.frame.midX
    let maximumOrigin = max(0, stack.frame.width - contentView.bounds.width)
    let originX = min(max(0, selectedCenter - contentView.bounds.width / 2), maximumOrigin)
    contentView.scroll(to: NSPoint(x: originX, y: 0))
    reflectScrolledClipView(contentView)
}
```

Override layout only to react to viewport-size changes:

```swift
override func layout() {
    super.layout()
    updateCenteredLayout()
}
```

When `apply` changes selection at the same viewport width, reset `lastViewportWidth = -1` or pass `force: true`, ensuring every selection recenters.

- [ ] **Step 6: Add DEBUG geometry accessors**

Keep test surfaces under the existing `#if DEBUG` block:

```swift
func debugSelectedCenterInViewport() -> CGFloat? {
    guard let selectedButton else { return nil }
    return selectedButton.convert(NSPoint(x: selectedButton.bounds.midX, y: 0), to: contentView).x
}

func debugLeadingSpacerWidth() -> CGFloat { leadingSpacer.frame.width }
func debugTrailingSpacerWidth() -> CGFloat { trailingSpacer.frame.width }
```

If `XCTAssertEqual` cannot compare an optional center, unwrap it in the test helper with `XCTUnwrap` before comparison.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run the Step 3 command.

Expected: all `FilmstripViewTests` pass with zero failures. Existing selection callback and thumbnail-size tests remain green.

- [ ] **Step 8: Run complete verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox
```

Expected: the full suite passes with zero failures.

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh
```

Expected: Release build succeeds and produces `/Users/gaoyinrui/Documents/Codex/ImageView/.build/ImageView.app`.

- [ ] **Step 9: Commit**

```bash
git add Sources/ImageViewApp/Viewer/FilmstripView.swift Tests/ImageViewAppTests/FilmstripViewTests.swift
git commit -m "feat: center selected filmstrip thumbnail"
```

---

## Completion Checklist

- [ ] Middle, first, and last selections center within 0.5pt.
- [ ] Viewport resizing recomputes edge space and preserves centering.
- [ ] Nil, missing, and empty selections reset to the leading position.
- [ ] Thumbnail click selection and sizing remain unchanged.
- [ ] Full Swift tests and Release build pass.
