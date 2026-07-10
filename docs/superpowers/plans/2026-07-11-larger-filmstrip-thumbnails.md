# Larger Filmstrip Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enlarge filmstrip thumbnails and resize their overlay to preserve balanced padding.

**Architecture:** Keep sizing constants with the views that own them. `FilmstripView` owns thumbnail dimensions, while `MainWindowController` owns the overlay height constraint.

**Tech Stack:** Swift 6, AppKit, XCTest, Swift Package Manager

## Global Constraints

- Regular thumbnail size is 72 x 64 points.
- Selected thumbnail size is 86 x 76 points.
- Filmstrip overlay height is 98 points.
- Existing reveal, hover, auto-hide, spacing, inset, border, and corner behavior remains unchanged.

---

### Task 1: Resize Filmstrip Content

**Files:**
- Modify: `Tests/ImageViewAppTests/FilmstripViewTests.swift`
- Modify: `Sources/ImageViewApp/Viewer/FilmstripView.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`

**Interfaces:**
- Consumes: `FilmstripView.thumbnailSize(isSelected:) -> CGSize`
- Produces: `FilmstripView.regularThumbnailSize`, `FilmstripView.selectedThumbnailSize`, and `MainWindowController.filmstripOverlayHeight` with the approved values.

- [ ] **Step 1: Write the failing test**

```swift
func testFilmstripUsesReadableThumbnailAndOverlayDimensions() {
    XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: false), CGSize(width: 72, height: 64))
    XCTAssertEqual(FilmstripView.thumbnailSize(isSelected: true), CGSize(width: 86, height: 76))
    XCTAssertEqual(MainWindowController.filmstripOverlayHeight, 98)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FilmstripViewTests/testFilmstripUsesReadableThumbnailAndOverlayDimensions --disable-sandbox`

Expected: FAIL because the current values are 52 x 46, 64 x 58, and 82.

- [ ] **Step 3: Write minimal implementation**

```swift
static let regularThumbnailSize = CGSize(width: 72, height: 64)
static let selectedThumbnailSize = CGSize(width: 86, height: 76)
static let filmstripOverlayHeight: CGFloat = 98
```

- [ ] **Step 4: Run the focused and full test suites**

Run: `swift test --filter FilmstripViewTests/testFilmstripUsesReadableThumbnailAndOverlayDimensions --disable-sandbox`

Expected: PASS.

Run: `swift test --disable-sandbox`

Expected: All tests pass with zero failures.

- [ ] **Step 5: Build the app**

Run: `scripts/build-app.sh`

Expected: `.build/ImageView.app` is produced successfully.
