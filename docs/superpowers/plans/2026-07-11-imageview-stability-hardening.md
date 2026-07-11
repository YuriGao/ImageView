# ImageView Stability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 ImageView 已有浏览、编辑、GIF、SVG 和文件刷新能力中的正确性与稳定性风险，不增加新的产品功能。

**Architecture:** 保持 `ImageViewCore` 与 `ImageViewApp` 分层。加载阶段和 UI 门禁留在 App 层，图像成本、解码预算和元数据清洗留在 Core 层；每个风险先用独立回归测试证明，再做最小实现。

**Tech Stack:** Swift 6、AppKit、Combine、ImageIO、CoreGraphics、XCTest、Swift Package Manager。

---

## Global Constraints

- 仅支持既有产品能力，不增加第三方包或新的用户入口。
- 目标为 Apple Silicon、macOS 14+。
- GIF 动画帧预算固定为 `128 * 1024 * 1024` bytes。
- 复杂 SVG 必须完整系统解码或明确失败，禁止部分渲染。
- 所有生产代码修改前必须运行对应失败测试。
- 每个任务独立提交，最终运行完整测试和 App Bundle 构建。

### Task 1: Progressive loading state and edit safety

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write failing tests**

Use `ControlledImageLoader` to hold the full image while preview is visible. Call `applyEdit` and assert no edit is recorded. Add a second test that holds preview while full completes and asserts the full image publishes immediately:

```swift
XCTAssertEqual(viewModel.loadPhase, .preview)
viewModel.applyEdit(.rotateClockwise)
XCTAssertFalse(viewModel.hasUnsavedEdits)

try await fullLoader.resume(url: url)
await waitUntil { viewModel.loadPhase == .full }
XCTAssertEqual(viewModel.currentImage?.pixelSize, full.pixelSize)
```

Extend `MainWindowControllerTests` so crop/edit/save commands require `canEditCurrentImage`, while zoom and navigation still work for a preview.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --disable-sandbox --filter ViewerViewModelTests/testPreviewCannotBeEditedBeforeFullImageArrives
swift test --disable-sandbox --filter ViewerViewModelTests/testOpenPublishesFullImageWithoutWaitingForSlowPreview
```

Expected: compile or assertion failure because explicit load phase and edit gating do not exist.

- [ ] **Step 3: Implement loading phase and race**

Add:

```swift
enum ImageLoadPhase: Equatable { case empty, preview, full, failed }
@Published private(set) var loadPhase: ImageLoadPhase = .empty
var canEditCurrentImage: Bool { loadPhase == .full && currentImage != nil }
```

Use a task group that returns preview/full events in completion order. Publish preview only before full, publish full immediately and cancel the remaining preview. Keep generation checks before state writes. Guard `applyEdit`, crop, rotate/mirror and save in the ViewModel/controller and use the flag in menu validation.

- [ ] **Step 4: Verify GREEN**

```bash
swift test --disable-sandbox --filter ViewerViewModelTests
swift test --disable-sandbox --filter MainWindowControllerTests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ImageViewApp/Viewer/ViewerViewModel.swift Sources/ImageViewApp/MainWindowController.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift
git commit -m "fix: protect edits during progressive loading"
```

### Task 2: Stable zoom anchor

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`
- Test: `Tests/ImageViewAppTests/ImageCanvasViewTests.swift`

- [ ] **Step 1: Write failing anchor tests**

```swift
func testZoomAtCanvasCenterKeepsZeroOffset() {
    let canvas = ImageCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    canvas.image = makeDecodedImage(width: 400, height: 300)
    canvas.zoom(by: 2, around: CGPoint(x: 200, y: 150))
    XCTAssertEqual(canvas.offset.x, 0, accuracy: 0.001)
    XCTAssertEqual(canvas.offset.y, 0, accuracy: 0.001)
}
```

Add an off-center case at `(300, 150)` expecting offset `(-100, 0)`.

- [ ] **Step 2: Verify RED**

```bash
swift test --disable-sandbox --filter ImageCanvasViewTests/testZoomAtCanvasCenterKeepsZeroOffset
```

Expected: current implementation produces non-zero center offset.

- [ ] **Step 3: Correct coordinate space**

```swift
let center = CGPoint(x: bounds.midX, y: bounds.midY)
let anchor = CGPoint(x: point.x - center.x, y: point.y - center.y)
let proposed = CGPoint(
    x: anchor.x - (anchor.x - offset.x) * ratio,
    y: anchor.y - (anchor.y - offset.y) * ratio
)
offset = clampedOffset(for: proposed)
```

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --disable-sandbox --filter ImageCanvasViewTests
swift test --disable-sandbox --filter GestureCoordinatorTests
git add Sources/ImageViewApp/Viewer/ImageCanvasView.swift Tests/ImageViewAppTests/ImageCanvasViewTests.swift
git commit -m "fix: preserve zoom anchor on canvas"
```

### Task 3: GIF memory accounting and decode budget

**Files:**
- Modify: `Sources/ImageViewCore/Decode/ImageDecodeService.swift`
- Modify: `Sources/ImageViewCore/Decode/ImageCache.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Test: `Tests/ImageViewCoreTests/ImageDecodeServiceTests.swift`
- Test: `Tests/ImageViewCoreTests/ImageCacheTests.swift`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Write failing cost, budget and preload tests**

Build a decoded image with two frames and assert `decodedByteCost` equals the main image plus every frame. Use a tiny injected animation limit so a generated GIF returns a visible first frame and no materialized animation frames. Assert `.gif` cannot preload.

```swift
XCTAssertEqual(decoded.decodedByteCost, expectedMainCost + expectedFrameCosts)
XCTAssertTrue(limited.animationFrames.isEmpty)
XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.gif))
```

- [ ] **Step 2: Verify RED**

```bash
swift test --disable-sandbox --filter ImageDecodeServiceTests
swift test --disable-sandbox --filter ImageCacheTests
swift test --disable-sandbox --filter ViewerViewModelTests/testCanPreloadInBackgroundSkipsFallbackFormats
```

- [ ] **Step 3: Implement bounded decoding and cache-owned cost**

Add overflow-safe `DecodedImage.decodedByteCost`. Give `ImageDecodeService` an internal `animationByteLimit` defaulting to `128 * 1024 * 1024`; estimate total decoded frame bytes from ImageIO properties before creating frame images. Above the limit, return the main frame with an empty animation array. Change `ImageCache.insert` to calculate cost from the image and update all callers. Exclude GIF from neighbor preload.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --disable-sandbox --filter ImageDecodeServiceTests
swift test --disable-sandbox --filter ImageCacheTests
swift test --disable-sandbox --filter ViewerViewModelTests
git add Sources/ImageViewCore/Decode/ImageDecodeService.swift Sources/ImageViewCore/Decode/ImageCache.swift Sources/ImageViewApp/Viewer/ViewerViewModel.swift Tests/ImageViewCoreTests/ImageDecodeServiceTests.swift Tests/ImageViewCoreTests/ImageCacheTests.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift
git commit -m "fix: bound animated image memory"
```

### Task 4: Preserve metadata during edits

**Files:**
- Modify: `Sources/ImageViewCore/Editing/ImageEditingService.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Test: `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Write failing metadata test**

Generate a JPEG carrying orientation 6, EXIF capture time, TIFF make/model and GPS. Decode, edit and save with a metadata source URL. Reopen properties and assert:

```swift
XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:07:11 12:34:56")
XCTAssertEqual(tiff[kCGImagePropertyTIFFMake] as? String, "ImageView Test")
XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])
XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, output.width)
```

- [ ] **Step 2: Verify RED**

```bash
swift test --disable-sandbox --filter ImageEditingServiceTests/testSavePreservesCompatibleMetadataAndNormalizesOrientation
```

- [ ] **Step 3: Implement metadata sanitization**

Change the API to:

```swift
public func save(
    _ image: CGImage,
    to url: URL,
    format: SupportedImageFormat,
    metadataSourceURL: URL? = nil
) throws
```

Read source properties, preserve compatible EXIF/GPS/TIFF/IPTC/DPI and color-related fields, normalize root and TIFF orientation to 1, update pixel width/height, and remove stale thumbnail fields. Pass the sanitized dictionary to `CGImageDestinationAddImage`. Update original-save and save-as paths to pass the current source URL.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --disable-sandbox --filter ImageEditingServiceTests
swift test --disable-sandbox --filter ViewerViewModelTests
git add Sources/ImageViewCore/Editing/ImageEditingService.swift Sources/ImageViewApp/Viewer/ViewerViewModel.swift Tests/ImageViewCoreTests/ImageEditingServiceTests.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift
git commit -m "fix: preserve image metadata on save"
```

### Task 5: Honest SVG failure and robust file fingerprints

**Files:**
- Modify: `Sources/ImageViewCore/Decode/ImageDecodeService.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Test: `Tests/ImageViewCoreTests/ImageDecodeServiceTests.swift`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Write failing SVG and file tests**

Create a complex SVG with two separated colored shapes. A successful decode must contain both regions; failure is acceptable, but a one-shape partial image is not. Add real temporary-file tests for equal-size rewrite with restored mtime and equal-size atomic replacement.

```swift
try replacementData.write(to: url)
try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path)
XCTAssertNotEqual(CurrentFileVersion.read(at: url), originalVersion)
```

- [ ] **Step 2: Verify RED**

```bash
swift test --disable-sandbox --filter ImageDecodeServiceTests/testComplexSVGIsFullyDecodedOrFails
swift test --disable-sandbox --filter ViewerViewModelTests/testFileVersionDetectsSameSizeRewriteWithRestoredModificationDate
swift test --disable-sandbox --filter ViewerViewModelTests/testFileVersionDetectsAtomicReplacementWithSameSizeAndModificationDate
```

- [ ] **Step 3: Remove partial SVG renderer and use stat fingerprint**

Delete `decodeSimpleSVG` and `SVGParser`; keep ImageIO then NSImage, otherwise throw. Replace `CurrentFileVersion` with:

```swift
struct CurrentFileVersion: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let fileSize: Int64
    let modificationNanoseconds: Int64
    let changeNanoseconds: Int64
}
```

Populate with Darwin `stat`, combining seconds and nanoseconds with overflow-safe arithmetic.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --disable-sandbox --filter ImageDecodeServiceTests
swift test --disable-sandbox --filter ViewerViewModelTests
git add Sources/ImageViewCore/Decode/ImageDecodeService.swift Sources/ImageViewApp/Viewer/ViewerViewModel.swift Tests/ImageViewCoreTests/ImageDecodeServiceTests.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift
git commit -m "fix: harden svg and external file handling"
```

### Task 6: Clean resources and complete verification

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Exclude hand-copied app resources from SwiftPM warnings**

```swift
exclude: [
    "Resources/ImageView.icns",
    "Resources/Info.plist"
],
```

- [ ] **Step 2: Run full clean test suite**

```bash
swift package clean
swift test --disable-sandbox
```

Expected: every existing and new test passes and the unhandled-resource warning is absent.

- [ ] **Step 3: Build and inspect release app**

```bash
scripts/build-app.sh
test -x .build/ImageView.app/Contents/MacOS/ImageView
plutil -lint .build/ImageView.app/Contents/Info.plist
file .build/ImageView.app/Contents/MacOS/ImageView
```

Expected: release build succeeds, plist is valid, executable is arm64 Mach-O.

- [ ] **Step 4: Commit and audit**

```bash
git add Package.swift
git commit -m "build: clean package resources"
git diff --check main...HEAD
git status --short
git log --oneline main..HEAD
```

Expected: no whitespace errors, no uncommitted source changes, focused commits only.
