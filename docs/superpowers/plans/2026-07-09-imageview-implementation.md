# ImageView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS image viewer that opens one image from Finder, discovers same-folder images, and provides fast trackpad-first browsing with core file and editing actions.

**Architecture:** Use a Swift Package with a testable `ImageViewCore` library and an AppKit executable target named `ImageView`. Core owns formats, directory scanning, navigation state, decoding, caching, file actions, and editing; the AppKit target owns windows, canvas rendering, gestures, HUD, filmstrip, and app lifecycle.

**Tech Stack:** Swift 6 where available, Swift Package Manager, AppKit, SwiftUI for lightweight overlays, ImageIO, CoreGraphics, CoreImage, UniformTypeIdentifiers, XCTest.

## Global Constraints

- Minimum supported macOS version: macOS 14.
- Product is a native macOS app using Swift with AppKit for precise windowing, gestures, scrolling, zooming, and file integration.
- No network dependencies in v1; use system frameworks first for JPEG, PNG, GIF, TIFF, BMP, HEIC/HEIF, WebP, AVIF, and SVG preview capability.
- Opening a folder is not a primary entry point in v1.
- Same-directory browsing must not wait for all thumbnails or directory scanning before showing the current image.
- Delete must move files to Trash, never permanently delete.
- Editing writes only formats that the app can safely encode; unsupported edit-save paths show a clear error and keep the original file intact.
- File-changing operations must expose unsaved-state or confirmation behavior before destructive user-visible transitions.
- Keep commits frequent: one commit per task after tests pass.

---

## Planned File Structure

### Root

- `Package.swift`: SwiftPM package definition with `ImageViewCore`, `ImageView`, and `ImageViewCoreTests`.
- `README.md`: local development commands and current product scope.
- `scripts/build-app.sh`: builds a runnable `ImageView.app` bundle from the SwiftPM executable.
- `.gitignore`: ignores build products, `.swiftpm`, Xcode user state, and generated app bundles.

### Core Library

- `Sources/ImageViewCore/Models/ImageItem.swift`: immutable metadata for one browsable image.
- `Sources/ImageViewCore/Models/SupportedImageFormat.swift`: extension, UTI, and capability mapping.
- `Sources/ImageViewCore/Directory/NaturalSort.swift`: localized natural filename ordering.
- `Sources/ImageViewCore/Directory/DirectoryScanner.swift`: async same-folder image discovery.
- `Sources/ImageViewCore/Navigation/NavigationState.swift`: current index, previous/next lookup, rename/delete sequence updates.
- `Sources/ImageViewCore/Decode/ImageDecodeService.swift`: ImageIO/CoreGraphics decode, thumbnail creation, animated-image metadata.
- `Sources/ImageViewCore/Decode/ImageCache.swift`: bounded in-memory cache for decoded images and thumbnails.
- `Sources/ImageViewCore/Files/FileActions.swift`: Trash, rename, reveal in Finder, and copy path helpers.
- `Sources/ImageViewCore/Editing/EditOperation.swift`: rotate, crop, and mirror operation definitions.
- `Sources/ImageViewCore/Editing/ImageEditingService.swift`: applies edits and safely writes supported still-image formats.

### App Target

- `Sources/ImageViewApp/main.swift`: AppKit entry point.
- `Sources/ImageViewApp/AppDelegate.swift`: app lifecycle and file-open handling.
- `Sources/ImageViewApp/MainWindowController.swift`: window composition and command routing.
- `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`: bridges core services to UI state.
- `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`: AppKit canvas, zoom, pan, and render surface.
- `Sources/ImageViewApp/Viewer/GestureCoordinator.swift`: magnification, pan, swipe, double-click, and scroll behavior.
- `Sources/ImageViewApp/Viewer/HUDView.swift`: SwiftUI HUD hosted inside AppKit.
- `Sources/ImageViewApp/Viewer/FilmstripView.swift`: horizontal thumbnail strip.
- `Sources/ImageViewApp/Viewer/CropOverlayView.swift`: crop handles and crop confirmation UI.
- `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift`: unsupported or damaged image state.
- `Sources/ImageViewApp/Settings/AppSettings.swift`: persisted user preferences.

### Tests

- `Tests/ImageViewCoreTests/SupportedImageFormatTests.swift`
- `Tests/ImageViewCoreTests/NaturalSortTests.swift`
- `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`
- `Tests/ImageViewCoreTests/NavigationStateTests.swift`
- `Tests/ImageViewCoreTests/ImageCacheTests.swift`
- `Tests/ImageViewCoreTests/FileActionsTests.swift`
- `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`

---

### Task 1: Swift Package and App Skeleton

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Sources/ImageViewCore/ImageViewCore.swift`
- Create: `Sources/ImageViewApp/main.swift`
- Create: `Sources/ImageViewApp/AppDelegate.swift`
- Create: `Tests/ImageViewCoreTests/ImageViewCoreSmokeTests.swift`

**Interfaces:**
- Produces: `public enum ImageViewCoreVersion { public static let current: String }`
- Produces: AppKit executable target `ImageView`

- [ ] **Step 1: Write the smoke test**

Create `Tests/ImageViewCoreTests/ImageViewCoreSmokeTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class ImageViewCoreSmokeTests: XCTestCase {
    func testCoreVersionIsAvailable() {
        XCTAssertEqual(ImageViewCoreVersion.current, "0.1.0")
    }
}
```

- [ ] **Step 2: Add the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageView",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ImageViewCore", targets: ["ImageViewCore"]),
        .executable(name: "ImageView", targets: ["ImageViewApp"])
    ],
    targets: [
        .target(
            name: "ImageViewCore",
            path: "Sources/ImageViewCore"
        ),
        .executableTarget(
            name: "ImageViewApp",
            dependencies: ["ImageViewCore"],
            path: "Sources/ImageViewApp"
        ),
        .testTarget(
            name: "ImageViewCoreTests",
            dependencies: ["ImageViewCore"],
            path: "Tests/ImageViewCoreTests"
        )
    ]
)
```

- [ ] **Step 3: Add minimal core and app entry point**

Create `Sources/ImageViewCore/ImageViewCore.swift`:

```swift
public enum ImageViewCoreVersion {
    public static let current = "0.1.0"
}
```

Create `Sources/ImageViewApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

Create `Sources/ImageViewApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 4: Add repo hygiene and docs**

Create `.gitignore`:

```gitignore
.build/
.swiftpm/
DerivedData/
*.xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.app/
.DS_Store
```

Create `README.md`:

````markdown
# ImageView

Native macOS image viewer intended to replace Preview for fast same-folder image browsing.

## Development

```bash
swift test
swift run ImageView
```

The PRD lives at `docs/superpowers/specs/2026-07-09-imageview-prd.md`.
````

- [ ] **Step 5: Run tests and app build**

Run: `swift test`

Expected: PASS with `ImageViewCoreSmokeTests.testCoreVersionIsAvailable`.

Run: `swift build`

Expected: PASS and executable target `ImageView` builds.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore README.md Sources Tests
git commit -m "chore: scaffold native ImageView package"
```

---

### Task 2: Format Detection and Same-Folder Scanning

**Files:**
- Create: `Sources/ImageViewCore/Models/SupportedImageFormat.swift`
- Create: `Sources/ImageViewCore/Models/ImageItem.swift`
- Create: `Sources/ImageViewCore/Directory/NaturalSort.swift`
- Create: `Sources/ImageViewCore/Directory/DirectoryScanner.swift`
- Create: `Tests/ImageViewCoreTests/SupportedImageFormatTests.swift`
- Create: `Tests/ImageViewCoreTests/NaturalSortTests.swift`
- Create: `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`

**Interfaces:**
- Produces: `public enum SupportedImageFormat: String, CaseIterable`
- Produces: `public struct ImageItem: Equatable, Identifiable`
- Produces: `public struct NaturalSort { public static func compare(_ lhs: String, _ rhs: String) -> Bool }`
- Produces: `public final class DirectoryScanner { public func scan(containing openedFile: URL) async throws -> [ImageItem] }`

- [ ] **Step 1: Write format tests**

Create `Tests/ImageViewCoreTests/SupportedImageFormatTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class SupportedImageFormatTests: XCTestCase {
    func testRequiredExtensionsAreSupported() {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp", "avif", "svg"]
        for ext in extensions {
            XCTAssertNotNil(SupportedImageFormat(fileExtension: ext), ext)
        }
    }

    func testUnsupportedExtensionReturnsNil() {
        XCTAssertNil(SupportedImageFormat(fileExtension: "txt"))
    }
}
```

- [ ] **Step 2: Write natural sort tests**

Create `Tests/ImageViewCoreTests/NaturalSortTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class NaturalSortTests: XCTestCase {
    func testSortsNumbersNaturally() {
        let names = ["image-10.png", "image-2.png", "image-1.png"]
        XCTAssertEqual(names.sorted(by: NaturalSort.compare), ["image-1.png", "image-2.png", "image-10.png"])
    }
}
```

- [ ] **Step 3: Write directory scanner tests**

Create `Tests/ImageViewCoreTests/DirectoryScannerTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class DirectoryScannerTests: XCTestCase {
    func testScansOnlySupportedImagesInOpenedFilesDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opened = root.appendingPathComponent("image-2.png")
        let first = root.appendingPathComponent("image-1.jpg")
        let ignored = root.appendingPathComponent("notes.txt")
        FileManager.default.createFile(atPath: opened.path, contents: Data())
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: ignored.path, contents: Data())

        let items = try await DirectoryScanner().scan(containing: opened)

        XCTAssertEqual(items.map(\.url.lastPathComponent), ["image-1.jpg", "image-2.png"])
        XCTAssertTrue(items.contains { $0.url == opened })
    }
}
```

- [ ] **Step 4: Implement format and item models**

Create `Sources/ImageViewCore/Models/SupportedImageFormat.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

public enum SupportedImageFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case gif
    case tiff
    case bmp
    case heic
    case heif
    case webp
    case avif
    case svg

    public init?(fileExtension: String) {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "jpg", "jpeg": self = .jpeg
        case "png": self = .png
        case "gif": self = .gif
        case "tif", "tiff": self = .tiff
        case "bmp": self = .bmp
        case "heic": self = .heic
        case "heif": self = .heif
        case "webp": self = .webp
        case "avif": self = .avif
        case "svg": self = .svg
        default: return nil
        }
    }

    public var canAttemptSafeWrite: Bool {
        switch self {
        case .jpeg, .png, .tiff, .bmp, .heic, .heif:
            return true
        case .gif, .webp, .avif, .svg:
            return false
        }
    }
}
```

Create `Sources/ImageViewCore/Models/ImageItem.swift`:

```swift
import Foundation

public struct ImageItem: Equatable, Identifiable, Sendable {
    public let id: URL
    public let url: URL
    public let format: SupportedImageFormat

    public init(url: URL, format: SupportedImageFormat) {
        self.id = url
        self.url = url
        self.format = format
    }
}
```

- [ ] **Step 5: Implement natural sort and scanner**

Create `Sources/ImageViewCore/Directory/NaturalSort.swift`:

```swift
import Foundation

public struct NaturalSort {
    public static func compare(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
```

Create `Sources/ImageViewCore/Directory/DirectoryScanner.swift`:

```swift
import Foundation

public final class DirectoryScanner: Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(containing openedFile: URL) async throws -> [ImageItem] {
        let directory = openedFile.deletingLastPathComponent()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url -> ImageItem? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                return nil
            }
            return ImageItem(url: url, format: format)
        }
        .sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter SupportedImageFormatTests`

Expected: PASS.

Run: `swift test --filter NaturalSortTests`

Expected: PASS.

Run: `swift test --filter DirectoryScannerTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ImageViewCore Tests/ImageViewCoreTests
git commit -m "feat: scan supported same-folder images"
```

---

### Task 3: Navigation State and Sequence Updates

**Files:**
- Create: `Sources/ImageViewCore/Navigation/NavigationState.swift`
- Create: `Tests/ImageViewCoreTests/NavigationStateTests.swift`

**Interfaces:**
- Consumes: `ImageItem`
- Produces: `public struct NavigationState: Equatable`
- Produces: `public init(items: [ImageItem], currentURL: URL)`
- Produces: `public var currentItem: ImageItem?`
- Produces: `public mutating func moveNext()`
- Produces: `public mutating func movePrevious()`
- Produces: `public mutating func removeCurrent()`
- Produces: `public mutating func replaceCurrentURL(_ newURL: URL, format: SupportedImageFormat)`

- [ ] **Step 1: Write navigation tests**

Create `Tests/ImageViewCoreTests/NavigationStateTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class NavigationStateTests: XCTestCase {
    func testStartsAtOpenedFileAndMoves() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "b.png")
        state.moveNext()
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "c.png")
        state.movePrevious()
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "b.png")
    }

    func testRemoveCurrentKeepsNearestUsableItem() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        state.removeCurrent()

        XCTAssertEqual(state.items.map { $0.url.lastPathComponent }, ["a.png", "c.png"])
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "c.png")
    }

    func testReplaceCurrentURLResortsSequence() {
        let items = makeItems(["a.png", "b.png", "c.png"])
        var state = NavigationState(items: items, currentURL: items[1].url)

        state.replaceCurrentURL(URL(fileURLWithPath: "/tmp/d.png"), format: .png)

        XCTAssertEqual(state.items.map { $0.url.lastPathComponent }, ["a.png", "c.png", "d.png"])
        XCTAssertEqual(state.currentItem?.url.lastPathComponent, "d.png")
    }

    private func makeItems(_ names: [String]) -> [ImageItem] {
        names.map { ImageItem(url: URL(fileURLWithPath: "/tmp/\($0)"), format: .png) }
    }
}
```

- [ ] **Step 2: Implement navigation state**

Create `Sources/ImageViewCore/Navigation/NavigationState.swift`:

```swift
import Foundation

public struct NavigationState: Equatable, Sendable {
    public private(set) var items: [ImageItem]
    public private(set) var currentIndex: Int?

    public init(items: [ImageItem], currentURL: URL) {
        self.items = items.sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
        self.currentIndex = self.items.firstIndex { $0.url == currentURL } ?? self.items.firstIndex { $0.url.standardizedFileURL == currentURL.standardizedFileURL }
    }

    public var currentItem: ImageItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public var canMovePrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    public var canMoveNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex < items.count - 1
    }

    public mutating func movePrevious() {
        guard canMovePrevious, let currentIndex else { return }
        self.currentIndex = currentIndex - 1
    }

    public mutating func moveNext() {
        guard canMoveNext, let currentIndex else { return }
        self.currentIndex = currentIndex + 1
    }

    public mutating func removeCurrent() {
        guard let currentIndex, items.indices.contains(currentIndex) else { return }
        items.remove(at: currentIndex)
        if items.isEmpty {
            self.currentIndex = nil
        } else {
            self.currentIndex = min(currentIndex, items.count - 1)
        }
    }

    public mutating func replaceCurrentURL(_ newURL: URL, format: SupportedImageFormat) {
        guard let currentIndex, items.indices.contains(currentIndex) else { return }
        items[currentIndex] = ImageItem(url: newURL, format: format)
        items.sort { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
        self.currentIndex = items.firstIndex { $0.url == newURL }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter NavigationStateTests`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/ImageViewCore/Navigation Tests/ImageViewCoreTests/NavigationStateTests.swift
git commit -m "feat: add image navigation state"
```

---

### Task 4: Decode Service, Thumbnail Generation, and Memory Cache

**Files:**
- Create: `Sources/ImageViewCore/Decode/ImageDecodeService.swift`
- Create: `Sources/ImageViewCore/Decode/ImageCache.swift`
- Create: `Tests/ImageViewCoreTests/ImageCacheTests.swift`

**Interfaces:**
- Consumes: `SupportedImageFormat`
- Produces: `public struct DecodedImage`
- Produces: `public final class ImageDecodeService`
- Produces: `public actor ImageCache`
- Produces: `public func decode(url: URL, format: SupportedImageFormat, maxPixelSize: CGFloat?) throws -> DecodedImage`
- Produces: ImageIO decode path plus AppKit `NSImage` fallback for SVG preview and other system-readable still images.
- Produces: `public func image(for url: URL) -> DecodedImage?`
- Produces: `public func insert(_ image: DecodedImage, for url: URL, cost: Int)`

- [ ] **Step 1: Write cache tests**

Create `Tests/ImageViewCoreTests/ImageCacheTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ImageViewCore

final class ImageCacheTests: XCTestCase {
    func testCacheEvictsLeastRecentItemWhenCostLimitIsExceeded() async {
        let cache = ImageCache(costLimit: 10)
        let image = DecodedImage(cgImage: makeImage(), pixelSize: CGSize(width: 1, height: 1), isAnimated: false)

        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/a.png"), cost: 6)
        await cache.insert(image, for: URL(fileURLWithPath: "/tmp/b.png"), cost: 6)

        let first = await cache.image(for: URL(fileURLWithPath: "/tmp/a.png"))
        let second = await cache.image(for: URL(fileURLWithPath: "/tmp/b.png"))
        XCTAssertNil(first)
        XCTAssertNotNil(second)
    }

    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
```

- [ ] **Step 2: Implement decode service**

Create `Sources/ImageViewCore/Decode/ImageDecodeService.swift`:

```swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO

public struct DecodedImage: Sendable {
    public let cgImage: CGImage
    public let pixelSize: CGSize
    public let isAnimated: Bool

    public init(cgImage: CGImage, pixelSize: CGSize, isAnimated: Bool) {
        self.cgImage = cgImage
        self.pixelSize = pixelSize
        self.isAnimated = isAnimated
    }
}

public enum ImageDecodeError: Error, Equatable {
    case cannotCreateSource
    case cannotDecodeImage
}

public final class ImageDecodeService: Sendable {
    public init() {}

    public func decode(url: URL, format: SupportedImageFormat, maxPixelSize: CGFloat? = nil) throws -> DecodedImage {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let decoded = decodeImageIO(source: source, maxPixelSize: maxPixelSize) {
            return decoded
        }

        if format == .svg || format == .webp || format == .avif {
            return try decodeWithNSImage(url: url, maxPixelSize: maxPixelSize)
        }

        throw ImageDecodeError.cannotCreateSource
    }

    private func decodeImageIO(source: CGImageSource, maxPixelSize: CGFloat?) -> DecodedImage? {
        let options: [CFString: Any]
        if let maxPixelSize {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
        } else {
            options = [kCGImageSourceShouldCache: false]
        }

        let image: CGImage?
        if maxPixelSize == nil {
            image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        guard let image else { return nil }

        let count = CGImageSourceGetCount(source)
        return DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: image.width, height: image.height),
            isAnimated: count > 1
        )
    }

    private func decodeWithNSImage(url: URL, maxPixelSize: CGFloat?) throws -> DecodedImage {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw ImageDecodeError.cannotDecodeImage
        }
        let sourceSize = nsImage.size
        let scale: CGFloat
        if let maxPixelSize, max(sourceSize.width, sourceSize.height) > maxPixelSize {
            scale = maxPixelSize / max(sourceSize.width, sourceSize.height)
        } else {
            scale = 1
        }
        let outputSize = CGSize(width: max(1, sourceSize.width * scale), height: max(1, sourceSize.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width),
            pixelsHigh: Int(outputSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ImageDecodeError.cannotDecodeImage
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        nsImage.draw(in: CGRect(origin: .zero, size: outputSize))
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = bitmap.cgImage else {
            throw ImageDecodeError.cannotDecodeImage
        }
        return DecodedImage(cgImage: cgImage, pixelSize: outputSize, isAnimated: false)
    }
}
```

- [ ] **Step 3: Implement bounded cache**

Create `Sources/ImageViewCore/Decode/ImageCache.swift`:

```swift
import Foundation

public actor ImageCache {
    private struct Entry {
        let image: DecodedImage
        let cost: Int
        var lastAccess: UInt64
    }

    private var entries: [URL: Entry] = [:]
    private var totalCost: Int = 0
    private var tick: UInt64 = 0
    private let costLimit: Int

    public init(costLimit: Int) {
        self.costLimit = max(1, costLimit)
    }

    public func image(for url: URL) -> DecodedImage? {
        guard var entry = entries[url] else { return nil }
        tick += 1
        entry.lastAccess = tick
        entries[url] = entry
        return entry.image
    }

    public func insert(_ image: DecodedImage, for url: URL, cost: Int) {
        let normalizedCost = max(1, cost)
        if let existing = entries[url] {
            totalCost -= existing.cost
        }
        tick += 1
        entries[url] = Entry(image: image, cost: normalizedCost, lastAccess: tick)
        totalCost += normalizedCost
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while totalCost > costLimit, let victim = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            entries.removeValue(forKey: victim.key)
            totalCost -= victim.value.cost
        }
    }
}
```

- [ ] **Step 4: Run tests**

Add a decode smoke test for generated PNG and an SVG fixture in `Tests/ImageViewCoreTests/ImageDecodeServiceTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class ImageDecodeServiceTests: XCTestCase {
    func testDecodeSvgThroughSystemFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("icon.svg")
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16' fill='red'/></svg>"
        try svg.data(using: .utf8)!.write(to: url)

        let decoded = try ImageDecodeService().decode(url: url, format: .svg, maxPixelSize: 64)

        XCTAssertEqual(decoded.pixelSize.width, 16)
        XCTAssertEqual(decoded.pixelSize.height, 16)
    }
}
```

Run: `swift test --filter ImageCacheTests`

Expected: PASS.

Run: `swift test --filter ImageDecodeServiceTests`

Expected: PASS on macOS 14 when AppKit can rasterize the SVG fixture; if this fails, implement the same interface with a `WKWebView` snapshot renderer before committing Task 4.

Run: `swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ImageViewCore/Decode Tests/ImageViewCoreTests/ImageCacheTests.swift
git commit -m "feat: decode and cache images"
```

---

### Task 5: App Window, View Model, and First Image Open

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Create: `Sources/ImageViewApp/MainWindowController.swift`
- Create: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Create: `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`
- Create: `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift`

**Interfaces:**
- Consumes: `DirectoryScanner`, `NavigationState`, `ImageDecodeService`
- Produces: `@MainActor final class ViewerViewModel`
- Produces: `func open(url: URL) async`
- Produces: `final class MainWindowController: NSWindowController`
- Produces: `final class ImageCanvasView: NSView`

- [ ] **Step 1: Implement view model**

Create `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`:

```swift
import AppKit
import Foundation
import ImageViewCore

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published private(set) var navigationState: NavigationState?
    @Published private(set) var currentImage: DecodedImage?
    @Published private(set) var errorMessage: String?

    private let scanner = DirectoryScanner()
    private let decoder = ImageDecodeService()
    private let cache = ImageCache(costLimit: 512 * 1024 * 1024)

    func open(url: URL) async {
        errorMessage = nil
        do {
            let format = SupportedImageFormat(fileExtension: url.pathExtension)
            let fallbackItems = format.map { [ImageItem(url: url, format: $0)] } ?? []
            navigationState = NavigationState(items: fallbackItems, currentURL: url)
            try await display(url: url)

            let items = try await scanner.scan(containing: url)
            navigationState = NavigationState(items: items, currentURL: url)
            preloadNeighbors()
        } catch {
            errorMessage = "无法打开图片：\(url.lastPathComponent)"
        }
    }

    func showNext() {
        navigationState?.moveNext()
        Task { await displayCurrentAndPreload() }
    }

    func showPrevious() {
        navigationState?.movePrevious()
        Task { await displayCurrentAndPreload() }
    }

    private func displayCurrentAndPreload() async {
        guard let url = navigationState?.currentItem?.url else { return }
        try? await display(url: url)
        preloadNeighbors()
    }

    private func display(url: URL) async throws {
        if let cached = await cache.image(for: url) {
            currentImage = cached
            return
        }
        let format = navigationState?.currentItem?.format ?? SupportedImageFormat(fileExtension: url.pathExtension) ?? .png
        let decoded = try decoder.decode(url: url, format: format)
        await cache.insert(decoded, for: url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
        currentImage = decoded
    }

    private func preloadNeighbors() {
        guard let state = navigationState, let current = state.currentItem else { return }
        let currentURL = current.url
        let neighbors = state.items.filter { item in
            abs((state.items.firstIndex(of: item) ?? 0) - (state.items.firstIndex { $0.url == currentURL } ?? 0)) <= 2
        }
        Task.detached { [decoder, cache] in
            for item in neighbors {
                if await cache.image(for: item.url) == nil, let decoded = try? decoder.decode(url: item.url, format: item.format) {
                    await cache.insert(decoded, for: item.url, cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Implement canvas and error overlay**

Create `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`:

```swift
import AppKit
import ImageViewCore

final class ImageCanvasView: NSView {
    var image: DecodedImage? {
        didSet { needsDisplay = true }
    }

    var scale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    var offset: CGPoint = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image else { return }

        let imageSize = CGSize(width: image.cgImage.width, height: image.cgImage.height)
        let fittedScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawScale = fittedScale * scale
        let drawSize = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
        let origin = CGPoint(
            x: (bounds.width - drawSize.width) / 2 + offset.x,
            y: (bounds.height - drawSize.height) / 2 + offset.y
        )

        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        NSGraphicsContext.current?.cgContext.draw(image.cgImage, in: CGRect(origin: origin, size: drawSize))
    }
}
```

Create `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift`:

```swift
import AppKit

final class ErrorOverlayView: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        drawsBackground = false
        textColor = .secondaryLabelColor
        alignment = .center
        font = .systemFont(ofSize: 15, weight: .medium)
        stringValue = ""
    }

    required init?(coder: NSCoder) {
        nil
    }
}
```

- [ ] **Step 3: Implement window controller**

Create `Sources/ImageViewApp/MainWindowController.swift`:

```swift
import AppKit
import Combine

final class MainWindowController: NSWindowController {
    private let viewModel = ViewerViewModel()
    private let canvas = ImageCanvasView()
    private let errorOverlay = ErrorOverlayView()
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        self.init(window: window)
        setup()
    }

    func open(url: URL) {
        Task { await viewModel.open(url: url) }
    }

    private func setup() {
        window?.titlebarAppearsTransparent = true
        window?.contentView = canvas
        canvas.addSubview(errorOverlay)
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorOverlay.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorOverlay.centerYAnchor.constraint(equalTo: canvas.centerYAnchor)
        ])

        viewModel.$currentImage.sink { [weak self] image in
            self?.canvas.image = image
            self?.window?.title = self?.viewModel.navigationState?.currentItem?.url.lastPathComponent ?? "ImageView"
        }.store(in: &cancellables)

        viewModel.$errorMessage.sink { [weak self] message in
            self?.errorOverlay.stringValue = message ?? ""
        }.store(in: &cancellables)
    }
}
```

- [ ] **Step 4: Route app open events**

Modify `Sources/ImageViewApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindowIfNeeded()
        for url in pendingOpenURLs {
            mainWindowController?.open(url: url)
        }
        pendingOpenURLs.removeAll()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindowIfNeeded()
        if mainWindowController == nil {
            pendingOpenURLs.append(contentsOf: urls)
        } else if let first = urls.first {
            mainWindowController?.open(url: first)
        }
    }

    private func showWindowIfNeeded() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
    }
}
```

- [ ] **Step 5: Build and manually open**

Run: `swift build`

Expected: PASS.

Run: `swift run ImageView`

Expected: A black ImageView window opens.

Manual check: drag or open a supported image through app open events after Task 10 bundles the app; for this task, verify view model by adding a temporary launch argument only during local debugging and removing it before commit.

- [ ] **Step 6: Commit**

```bash
git add Sources/ImageViewApp
git commit -m "feat: display opened images in AppKit window"
```

---

### Task 6: Gesture, Keyboard, HUD, and Filmstrip Navigation

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Modify: `Sources/ImageViewApp/Viewer/ImageCanvasView.swift`
- Create: `Sources/ImageViewApp/Viewer/GestureCoordinator.swift`
- Create: `Sources/ImageViewApp/Viewer/HUDView.swift`
- Create: `Sources/ImageViewApp/Viewer/FilmstripView.swift`

**Interfaces:**
- Consumes: `ViewerViewModel.showNext()`, `ViewerViewModel.showPrevious()`
- Produces: `final class GestureCoordinator`
- Produces: `struct HUDView: View`
- Produces: `final class FilmstripView: NSScrollView`

- [ ] **Step 1: Add canvas gesture hooks**

Modify `Sources/ImageViewApp/Viewer/ImageCanvasView.swift` so it includes:

```swift
var onNext: (() -> Void)?
var onPrevious: (() -> Void)?

func resetViewTransform() {
    scale = 1.0
    offset = .zero
}

func zoom(by delta: CGFloat, around point: CGPoint) {
    let previousScale = scale
    scale = min(max(scale * delta, 0.1), 12.0)
    let ratio = scale / previousScale
    offset = CGPoint(
        x: point.x - (point.x - offset.x) * ratio,
        y: point.y - (point.y - offset.y) * ratio
    )
}

func pan(by delta: CGPoint) {
    offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
}

func toggleFitOrActualSize() {
    if abs(scale - 1.0) < 0.01 {
        scale = 2.0
    } else {
        resetViewTransform()
    }
}
```

- [ ] **Step 2: Implement gesture coordinator**

Create `Sources/ImageViewApp/Viewer/GestureCoordinator.swift`:

```swift
import AppKit

final class GestureCoordinator: NSObject {
    private weak var canvas: ImageCanvasView?

    init(canvas: ImageCanvasView) {
        self.canvas = canvas
        super.init()
        install()
    }

    private func install() {
        let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        click.numberOfClicksRequired = 2
        canvas?.addGestureRecognizer(magnification)
        canvas?.addGestureRecognizer(pan)
        canvas?.addGestureRecognizer(click)
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let canvas else { return }
        let point = gesture.location(in: canvas)
        canvas.zoom(by: 1.0 + gesture.magnification, around: point)
        gesture.magnification = 0
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let canvas else { return }
        let translation = gesture.translation(in: canvas)
        if canvas.scale > 1.01 {
            canvas.pan(by: CGPoint(x: translation.x, y: translation.y))
        } else if gesture.state == .ended {
            if translation.x < -80 { canvas.onNext?() }
            if translation.x > 80 { canvas.onPrevious?() }
        }
        gesture.setTranslation(.zero, in: canvas)
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        canvas?.toggleFitOrActualSize()
    }
}
```

- [ ] **Step 3: Add keyboard routing and HUD**

Create `Sources/ImageViewApp/Viewer/HUDView.swift`:

```swift
import SwiftUI

struct HUDView: View {
    let filename: String
    let positionText: String
    let zoomText: String
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(filename)
            Text(positionText)
            Text(zoomText)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isPinned ? 1.0 : 0.92)
    }
}
```

Modify `MainWindowController` to set:

```swift
canvas.onNext = { [weak self] in self?.viewModel.showNext() }
canvas.onPrevious = { [weak self] in self?.viewModel.showPrevious() }
_ = GestureCoordinator(canvas: canvas)
```

Override key handling in `MainWindowController`:

```swift
override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123:
        viewModel.showPrevious()
    case 124:
        viewModel.showNext()
    case 49:
        canvas.toggleFitOrActualSize()
    case 36:
        window?.toggleFullScreen(nil)
    case 53:
        window?.endEditing(for: nil)
    default:
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 4: Add filmstrip shell**

Create `Sources/ImageViewApp/Viewer/FilmstripView.swift`:

```swift
import AppKit
import ImageViewCore

final class FilmstripView: NSScrollView {
    private let stack = NSStackView()

    var onSelect: ((ImageItem) -> Void)?

    init() {
        super.init(frame: .zero)
        hasHorizontalScroller = true
        hasVerticalScroller = false
        drawsBackground = false
        stack.orientation = .horizontal
        stack.spacing = 6
        documentView = stack
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(items: [ImageItem], current: ImageItem?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let button = NSButton(title: item.url.deletingPathExtension().lastPathComponent, target: nil, action: nil)
            button.bezelStyle = .texturedRounded
            button.contentTintColor = item == current ? .controlAccentColor : .secondaryLabelColor
            button.target = self
            button.action = #selector(selectItem(_:))
            button.representedObject = item.url
            stack.addArrangedSubview(button)
        }
    }

    @objc private func selectItem(_ sender: NSButton) {
        guard let url = sender.representedObject as? URL else { return }
        let format = SupportedImageFormat(fileExtension: url.pathExtension) ?? .png
        onSelect?(ImageItem(url: url, format: format))
    }
}
```

- [ ] **Step 5: Build and smoke test**

Run: `swift build`

Expected: PASS.

Manual check: open the app, use double-click zoom, trackpad pan, left/right keyboard, and Enter full screen.

- [ ] **Step 6: Commit**

```bash
git add Sources/ImageViewApp
git commit -m "feat: add viewer gestures and navigation UI"
```

---

### Task 7: File Actions

**Files:**
- Create: `Sources/ImageViewCore/Files/FileActions.swift`
- Create: `Tests/ImageViewCoreTests/FileActionsTests.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`

**Interfaces:**
- Produces: `public final class FileActions`
- Produces: `public func moveToTrash(_ url: URL) throws`
- Produces: `public func rename(_ url: URL, to newBaseName: String) throws -> URL`
- Produces: `public func absolutePath(for url: URL) -> String`

- [ ] **Step 1: Write file action tests**

Create `Tests/ImageViewCoreTests/FileActionsTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class FileActionsTests: XCTestCase {
    func testRenamePreservesExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))

        let renamed = try FileActions().rename(original, to: "new")

        XCTAssertEqual(renamed.lastPathComponent, "new.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testAbsolutePathReturnsPathString() {
        let url = URL(fileURLWithPath: "/tmp/a.png")
        XCTAssertEqual(FileActions().absolutePath(for: url), "/tmp/a.png")
    }
}
```

- [ ] **Step 2: Implement file actions**

Create `Sources/ImageViewCore/Files/FileActions.swift`:

```swift
import AppKit
import Foundation

public enum FileActionError: Error, Equatable {
    case emptyName
    case unsupportedRenameTarget
}

public final class FileActions {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    public func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FileActionError.emptyName }
        let ext = url.pathExtension
        guard !ext.isEmpty else { throw FileActionError.unsupportedRenameTarget }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed).appendingPathExtension(ext)
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func absolutePath(for url: URL) -> String {
        url.path
    }
}
```

- [ ] **Step 3: Wire delete, rename, reveal, and copy path into view model**

Modify `ViewerViewModel` to include:

```swift
private let fileActions = FileActions()

func moveCurrentToTrash() {
    guard let url = navigationState?.currentItem?.url else { return }
    do {
        try fileActions.moveToTrash(url)
        navigationState?.removeCurrent()
        Task { await displayCurrentAndPreload() }
    } catch {
        errorMessage = "无法移动到废纸篓：\(url.lastPathComponent)"
    }
}

func renameCurrent(to newBaseName: String) {
    guard let item = navigationState?.currentItem else { return }
    do {
        let newURL = try fileActions.rename(item.url, to: newBaseName)
        navigationState?.replaceCurrentURL(newURL, format: item.format)
    } catch {
        errorMessage = "无法重命名：\(item.url.lastPathComponent)"
    }
}

func revealCurrentInFinder() {
    guard let url = navigationState?.currentItem?.url else { return }
    fileActions.revealInFinder(url)
}

func copyCurrentPathToPasteboard() {
    guard let url = navigationState?.currentItem?.url else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(fileActions.absolutePath(for: url), forType: .string)
}
```

- [ ] **Step 4: Add keyboard delete routing**

Modify `MainWindowController.keyDown(with:)`:

```swift
case 51:
    viewModel.moveCurrentToTrash()
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter FileActionsTests`

Expected: PASS.

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ImageViewCore/Files Tests/ImageViewCoreTests/FileActionsTests.swift Sources/ImageViewApp
git commit -m "feat: add current image file actions"
```

---

### Task 8: Basic Editing and Unsaved-State Guard

**Files:**
- Create: `Sources/ImageViewCore/Editing/EditOperation.swift`
- Create: `Sources/ImageViewCore/Editing/ImageEditingService.swift`
- Create: `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Create: `Sources/ImageViewApp/Viewer/CropOverlayView.swift`

**Interfaces:**
- Produces: `public enum EditOperation`
- Produces: `public final class ImageEditingService`
- Produces: `public func apply(_ operations: [EditOperation], to image: CGImage) throws -> CGImage`
- Produces: `public func save(_ image: CGImage, to url: URL, format: SupportedImageFormat) throws`

- [ ] **Step 1: Write editing tests**

Create `Tests/ImageViewCoreTests/ImageEditingServiceTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import ImageViewCore

final class ImageEditingServiceTests: XCTestCase {
    func testHorizontalMirrorKeepsImageSize() throws {
        let image = makeImage(width: 3, height: 2)
        let result = try ImageEditingService().apply([.mirrorHorizontal], to: image)
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 2)
    }

    func testUnsupportedSaveFormatThrows() {
        let image = makeImage(width: 2, height: 2)
        XCTAssertThrowsError(try ImageEditingService().save(image, to: URL(fileURLWithPath: "/tmp/a.svg"), format: .svg))
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
```

- [ ] **Step 2: Implement edit operations**

Create `Sources/ImageViewCore/Editing/EditOperation.swift`:

```swift
import CoreGraphics

public enum EditOperation: Equatable, Sendable {
    case rotateClockwise
    case rotateCounterClockwise
    case mirrorHorizontal
    case mirrorVertical
    case crop(CGRect)
}
```

- [ ] **Step 3: Implement editing service**

Create `Sources/ImageViewCore/Editing/ImageEditingService.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageEditingError: Error, Equatable {
    case cannotCreateContext
    case cannotCreateImage
    case unsupportedSaveFormat
    case cannotCreateDestination
    case saveFailed
}

public final class ImageEditingService {
    public init() {}

    public func apply(_ operations: [EditOperation], to image: CGImage) throws -> CGImage {
        try operations.reduce(image) { current, operation in
            switch operation {
            case .rotateClockwise:
                return try transform(current, radians: .pi / 2, scaleX: 1, scaleY: 1)
            case .rotateCounterClockwise:
                return try transform(current, radians: -.pi / 2, scaleX: 1, scaleY: 1)
            case .mirrorHorizontal:
                return try transform(current, radians: 0, scaleX: -1, scaleY: 1)
            case .mirrorVertical:
                return try transform(current, radians: 0, scaleX: 1, scaleY: -1)
            case .crop(let rect):
                guard let cropped = current.cropping(to: rect) else { throw ImageEditingError.cannotCreateImage }
                return cropped
            }
        }
    }

    public func save(_ image: CGImage, to url: URL, format: SupportedImageFormat) throws {
        guard format.canAttemptSafeWrite, let uti = uti(for: format) else {
            throw ImageEditingError.unsupportedSaveFormat
        }
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).imageview-tmp")
        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, uti as CFString, 1, nil) else {
            throw ImageEditingError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageEditingError.saveFailed
        }
        try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }

    private func transform(_ image: CGImage, radians: CGFloat, scaleX: CGFloat, scaleY: CGFloat) throws -> CGImage {
        let rotated = abs(radians) == .pi / 2
        let width = rotated ? image.height : image.width
        let height = rotated ? image.width : image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { throw ImageEditingError.cannotCreateContext }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: radians)
        context.scaleBy(x: scaleX, y: scaleY)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: image.width, height: image.height))
        guard let output = context.makeImage() else { throw ImageEditingError.cannotCreateImage }
        return output
    }

    private func uti(for format: SupportedImageFormat) -> String? {
        switch format {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .tiff: return UTType.tiff.identifier
        case .bmp: return UTType.bmp.identifier
        case .heic, .heif: return UTType.heic.identifier
        case .gif, .webp, .avif, .svg: return nil
        }
    }
}
```

- [ ] **Step 4: Add unsaved-state to view model**

Modify `ViewerViewModel` to include:

```swift
@Published private(set) var hasUnsavedEdits = false
private let editingService = ImageEditingService()
private var pendingOperations: [EditOperation] = []

func applyEdit(_ operation: EditOperation) {
    guard let image = currentImage else { return }
    do {
        let output = try editingService.apply([operation], to: image.cgImage)
        currentImage = DecodedImage(cgImage: output, pixelSize: CGSize(width: output.width, height: output.height), isAnimated: false)
        pendingOperations.append(operation)
        hasUnsavedEdits = true
    } catch {
        errorMessage = "无法应用编辑"
    }
}

func saveCurrentEdits() {
    guard let item = navigationState?.currentItem, let image = currentImage else { return }
    do {
        try editingService.save(image.cgImage, to: item.url, format: item.format)
        pendingOperations.removeAll()
        hasUnsavedEdits = false
    } catch {
        errorMessage = "无法保存该格式的编辑结果"
    }
}

func discardCurrentEditsAndReload() {
    pendingOperations.removeAll()
    hasUnsavedEdits = false
    Task { await displayCurrentAndPreload() }
}
```

- [ ] **Step 5: Add crop overlay shell**

Create `Sources/ImageViewApp/Viewer/CropOverlayView.swift`:

```swift
import AppKit

final class CropOverlayView: NSView {
    var cropRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: cropRect).stroke()
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter ImageEditingServiceTests`

Expected: PASS.

Run: `swift test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ImageViewCore/Editing Sources/ImageViewApp/Viewer Tests/ImageViewCoreTests/ImageEditingServiceTests.swift
git commit -m "feat: add basic image editing"
```

---

### Task 9: Preferences, Error States, and Performance Guards

**Files:**
- Create: `Sources/ImageViewApp/Settings/AppSettings.swift`
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Modify: `Sources/ImageViewApp/Viewer/HUDView.swift`
- Modify: `Sources/ImageViewCore/Decode/ImageCache.swift`
- Create: `Tests/ImageViewCoreTests/PerformanceGuardTests.swift`

**Interfaces:**
- Produces: `final class AppSettings: ObservableObject`
- Produces: cache cost limit defaults
- Produces: user-facing decode and unsupported-format messages

- [ ] **Step 1: Add performance guard tests**

Create `Tests/ImageViewCoreTests/PerformanceGuardTests.swift`:

```swift
import XCTest
@testable import ImageViewCore

final class PerformanceGuardTests: XCTestCase {
    func testDirectoryScanDoesNotRequireImageDecoding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<1000 {
            FileManager.default.createFile(atPath: root.appendingPathComponent("image-\(index).png").path, contents: Data())
        }

        let opened = root.appendingPathComponent("image-500.png")
        let items = try await DirectoryScanner().scan(containing: opened)
        XCTAssertEqual(items.count, 1000)
    }
}
```

- [ ] **Step 2: Implement settings**

Create `Sources/ImageViewApp/Settings/AppSettings.swift`:

```swift
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var pinsHUD: Bool {
        didSet { UserDefaults.standard.set(pinsHUD, forKey: "pinsHUD") }
    }

    @Published var confirmsDelete: Bool {
        didSet { UserDefaults.standard.set(confirmsDelete, forKey: "confirmsDelete") }
    }

    @Published var usesBlackFullscreenBackground: Bool {
        didSet { UserDefaults.standard.set(usesBlackFullscreenBackground, forKey: "usesBlackFullscreenBackground") }
    }

    init() {
        pinsHUD = UserDefaults.standard.bool(forKey: "pinsHUD")
        confirmsDelete = UserDefaults.standard.object(forKey: "confirmsDelete") as? Bool ?? true
        usesBlackFullscreenBackground = UserDefaults.standard.object(forKey: "usesBlackFullscreenBackground") as? Bool ?? true
    }
}
```

- [ ] **Step 3: Add user-facing error mapping**

Modify `ViewerViewModel.open(url:)` to set these messages:

```swift
guard SupportedImageFormat(fileExtension: url.pathExtension) != nil else {
    errorMessage = "不支持的图片格式：\(url.pathExtension)"
    return
}
```

Modify decode failure handling to use:

```swift
errorMessage = "图片损坏或无法解码：\(url.lastPathComponent)"
```

- [ ] **Step 4: Add cache tuning constant**

Modify `ImageCache` to expose:

```swift
public static let defaultFullImageCostLimit = 512 * 1024 * 1024
public static let defaultThumbnailCostLimit = 128 * 1024 * 1024
```

Use `ImageCache.defaultFullImageCostLimit` in `ViewerViewModel`.

- [ ] **Step 5: Run tests**

Run: `swift test --filter PerformanceGuardTests`

Expected: PASS.

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests/ImageViewCoreTests/PerformanceGuardTests.swift
git commit -m "feat: add viewer preferences and performance guards"
```

---

### Task 10: App Bundle Script and Release Verification

**Files:**
- Create: `scripts/build-app.sh`
- Create: `Sources/ImageViewApp/Resources/Info.plist`
- Modify: `README.md`

**Interfaces:**
- Produces: `scripts/build-app.sh`
- Produces: `.build/ImageView.app`

- [ ] **Step 1: Add app Info.plist**

Create `Sources/ImageViewApp/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ImageView</string>
  <key>CFBundleIdentifier</key>
  <string>local.imageview.app</string>
  <key>CFBundleName</key>
  <string>ImageView</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Image Files</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.jpeg</string>
        <string>public.png</string>
        <string>com.compuserve.gif</string>
        <string>public.tiff</string>
        <string>com.microsoft.bmp</string>
        <string>public.heic</string>
        <string>public.heif</string>
        <string>org.webmproject.webp</string>
        <string>public.svg-image</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Add build script**

Create `scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/ImageView.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --configuration release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/ImageView" "$MACOS_DIR/ImageView"
cp "$ROOT_DIR/Sources/ImageViewApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
```

Then run: `chmod +x scripts/build-app.sh`

- [ ] **Step 3: Update README**

Modify `README.md` to include:

````markdown
## Build App Bundle

```bash
scripts/build-app.sh
open .build/ImageView.app
```

The bundle declares common image document types so macOS can offer it as an image viewer.
````

- [ ] **Step 4: Full verification**

Run: `swift test`

Expected: PASS.

Run: `scripts/build-app.sh`

Expected: prints `.build/ImageView.app` and exits 0.

Run: `open .build/ImageView.app`

Expected: ImageView launches as a regular macOS app.

Manual PRD checks:

1. Open a JPEG or PNG from Finder with ImageView.
2. Verify same-folder next/previous navigation.
3. Verify pinch zoom, pan, double-click zoom toggle, and keyboard arrows.
4. Verify Delete moves a copy of a test image to Trash.
5. Verify rename updates current UI state.
6. Verify rotate or mirror can save a test PNG.
7. Verify unsupported files show an error instead of crashing.

- [ ] **Step 5: Commit**

```bash
git add scripts Sources/ImageViewApp/Resources README.md
git commit -m "chore: package ImageView app bundle"
```
