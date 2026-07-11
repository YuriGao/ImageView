# Default Image Application Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a file-association section to ImageView Settings that assigns ImageView as the default application for selected image formats.

**Architecture:** A narrow `DefaultApplicationServicing` protocol isolates `NSWorkspace` reads and mutations. A main-actor `FileAssociationSettingsModel` owns temporary selection, expansion, progress, status, and retry behavior; `PreferencesWindowController` renders that model with native AppKit controls and localized strings.

**Tech Stack:** Swift 6, AppKit, UniformTypeIdentifiers, Combine, SwiftPM, XCTest, macOS 14+

## Global Constraints

- Keep the existing SwiftPM package and macOS 14 minimum deployment target.
- Use only Apple's AppKit and UniformTypeIdentifiers APIs; add no dependency and invoke no command-line association utility.
- Use `NSWorkspace`'s macOS 12+ content-type APIs; do not use deprecated Launch Services setters.
- Common formats are ordered JPEG, PNG, GIF, WebP, HEIC; expanded formats append TIFF, BMP, HEIF, AVIF, SVG.
- Modify only checked formats. Never restore Preview, assign another application, or mutate an unchecked format.
- Checkbox state is temporary and is not written to `AppSettings` or `UserDefaults`.
- Process selected formats sequentially, retain successful changes, and retain failed formats for retry without rollback.
- Localize every new user-facing string in English and Simplified Chinese through `AppStrings`.

---

## File Structure

- Create `Sources/ImageViewApp/Settings/DefaultApplicationService.swift`: production wrapper and injectable protocol for `NSWorkspace`.
- Create `Sources/ImageViewApp/Settings/FileAssociationSettingsModel.swift`: format ordering, transient state, orchestration, summaries, and refresh logic.
- Modify `Sources/ImageViewCore/Models/SupportedImageFormat.swift`: add explicit `Hashable` conformance for set and dictionary state.
- Modify `Sources/ImageViewApp/Settings/PreferencesWindowController.swift`: native AppKit rows and controls bound to the model.
- Modify `Sources/ImageViewApp/AppDelegate.swift`: inject the default-application service when creating Settings.
- Modify `Sources/ImageViewApp/Localization/AppStrings.swift`: register settings localization keys.
- Modify `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`: English copy.
- Modify `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`: Simplified Chinese copy.
- Create `Tests/ImageViewAppTests/DefaultApplicationServiceTests.swift`: verify the production wrapper through an `NSWorkspace` seam without changing real defaults.
- Create `Tests/ImageViewAppTests/FileAssociationSettingsModelTests.swift`: format order, selection, async result, retry, and invalid-bundle tests.
- Create `Tests/ImageViewAppTests/PreferencesWindowControllerTests.swift`: window composition, localization, and control-state tests.

---

### Task 1: Isolate the NSWorkspace Default-Application API

**Files:**
- Create: `Sources/ImageViewApp/Settings/DefaultApplicationService.swift`
- Create: `Tests/ImageViewAppTests/DefaultApplicationServiceTests.swift`

**Interfaces:**
- Consumes: `UniformTypeIdentifiers.UTType`, `AppKit.NSWorkspace`.
- Produces: `@MainActor protocol DefaultApplicationServicing`, `WorkspaceDefaultApplicationClient`, and `WorkspaceDefaultApplicationService`.

- [ ] **Step 1: Write failing service tests**

Create a workspace seam so tests verify argument forwarding but never modify the machine's real defaults:

```swift
import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewApp

@MainActor
final class DefaultApplicationServiceTests: XCTestCase {
    func testQueryForwardsContentTypeToWorkspaceClient() {
        let expected = URL(fileURLWithPath: "/Applications/Preview.app")
        let client = WorkspaceClientSpy(defaultURL: expected)
        let service = WorkspaceDefaultApplicationService(client: client)

        XCTAssertEqual(service.defaultApplicationURL(for: .png), expected)
        XCTAssertEqual(client.queriedTypes, [.png])
    }

    func testSetForwardsApplicationURLAndContentType() async throws {
        let client = WorkspaceClientSpy()
        let service = WorkspaceDefaultApplicationService(client: client)
        let appURL = URL(fileURLWithPath: "/Applications/ImageView.app")

        try await service.setDefaultApplication(at: appURL, for: .jpeg)

        XCTAssertEqual(client.setRequests.map(\.0), [appURL])
        XCTAssertEqual(client.setRequests.map(\.1), [.jpeg])
    }

    func testSetPropagatesWorkspaceError() async {
        let client = WorkspaceClientSpy(setError: TestError.denied)
        let service = WorkspaceDefaultApplicationService(client: client)

        await XCTAssertThrowsErrorAsync {
            try await service.setDefaultApplication(
                at: URL(fileURLWithPath: "/Applications/ImageView.app"),
                for: .gif
            )
        }
    }
}

private enum TestError: Error { case denied }

@MainActor
private final class WorkspaceClientSpy: WorkspaceDefaultApplicationClient {
    var queriedTypes: [UTType] = []
    var setRequests: [(URL, UTType)] = []
    let defaultURL: URL?
    let setError: Error?

    init(defaultURL: URL? = nil, setError: Error? = nil) {
        self.defaultURL = defaultURL
        self.setError = setError
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        queriedTypes.append(contentType)
        return defaultURL
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        setRequests.append((applicationURL, contentType))
        if let setError { throw setError }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
```

- [ ] **Step 2: Run the focused tests and confirm the expected failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter DefaultApplicationServiceTests
```

Expected: compilation fails because `WorkspaceDefaultApplicationService` and `WorkspaceDefaultApplicationClient` do not exist.

- [ ] **Step 3: Implement the protocol, client seam, and NSWorkspace adapter**

Create `DefaultApplicationService.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
protocol DefaultApplicationServicing: AnyObject {
    func defaultApplicationURL(for contentType: UTType) -> URL?
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws
}

@MainActor
protocol WorkspaceDefaultApplicationClient: AnyObject {
    func defaultApplicationURL(for contentType: UTType) -> URL?
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws
}

@MainActor
final class WorkspaceDefaultApplicationService: DefaultApplicationServicing {
    private let client: WorkspaceDefaultApplicationClient

    init(client: WorkspaceDefaultApplicationClient = NSWorkspace.shared) {
        self.client = client
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        client.defaultApplicationURL(for: contentType)
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        try await client.setDefaultApplication(at: applicationURL, for: contentType)
    }
}

extension NSWorkspace: WorkspaceDefaultApplicationClient {
    func defaultApplicationURL(for contentType: UTType) -> URL? {
        urlForApplication(toOpen: contentType)
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        try await withCheckedThrowingContinuation { continuation in
            setDefaultApplication(at: applicationURL, toOpen: contentType) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the focused tests and confirm they pass**

Run the Step 2 command.

Expected: 3 tests pass with zero failures and no real default association changes.

- [ ] **Step 5: Commit the service boundary**

```bash
git add Sources/ImageViewApp/Settings/DefaultApplicationService.swift Tests/ImageViewAppTests/DefaultApplicationServiceTests.swift
git commit -m "feat: add default application service"
```

---

### Task 2: Model Format Selection and Apply Results

**Files:**
- Create: `Sources/ImageViewApp/Settings/FileAssociationSettingsModel.swift`
- Modify: `Sources/ImageViewCore/Models/SupportedImageFormat.swift`
- Create: `Tests/ImageViewAppTests/FileAssociationSettingsModelTests.swift`

**Interfaces:**
- Consumes: `DefaultApplicationServicing`, `ImageViewCore.SupportedImageFormat`, `SupportedImageFormat.contentType`.
- Produces: `@MainActor final class FileAssociationSettingsModel`, `FileAssociationRowState`, `FileAssociationSummary`, `commonFormats`, `allFormats`, `toggleSelection(for:)`, `selectCommonFormats()`, `setShowsAllFormats(_:)`, `refreshStatuses()`, and `applySelectedFormats()`.

- [ ] **Step 1: Write failing model tests for ordering and transient selection**

```swift
import UniformTypeIdentifiers
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class FileAssociationSettingsModelTests: XCTestCase {
    func testCommonAndExpandedFormatOrdering() {
        let model = makeModel()
        XCTAssertEqual(model.visibleFormats, [.jpeg, .png, .gif, .webp, .heic])

        model.setShowsAllFormats(true)

        XCTAssertEqual(model.visibleFormats, [
            .jpeg, .png, .gif, .webp, .heic,
            .tiff, .bmp, .heif, .avif, .svg
        ])
    }

    func testSelectCommonFormatsPreservesExtraSelections() {
        let model = makeModel()
        model.toggleSelection(for: .svg)

        model.selectCommonFormats()

        XCTAssertEqual(model.selectedFormats, Set([
            .jpeg, .png, .gif, .webp, .heic, .svg
        ]))
    }

    func testCollapsePreservesHiddenSelection() {
        let model = makeModel()
        model.setShowsAllFormats(true)
        model.toggleSelection(for: .avif)

        model.setShowsAllFormats(false)

        XCTAssertTrue(model.selectedFormats.contains(.avif))
    }
}
```

- [ ] **Step 2: Write failing model tests for refresh, success, partial failure, and invalid bundles**

Add tests using the fake below:

```swift
func testRefreshReportsImageViewAndOtherApplicationNames() {
    let imageViewURL = URL(fileURLWithPath: "/Applications/ImageView.app")
    let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
    let service = DefaultApplicationServiceFake(defaults: [
        UTType.jpeg: imageViewURL,
        UTType.png: previewURL
    ])
    let model = makeModel(service: service, appURL: imageViewURL)

    model.refreshStatuses()

    XCTAssertEqual(model.rows[.jpeg]?.defaultApplicationName, "ImageView")
    XCTAssertTrue(model.rows[.jpeg]?.isImageViewDefault == true)
    XCTAssertEqual(model.rows[.png]?.defaultApplicationName, "Preview")
}

func testApplyChangesOnlySelectedFormatsAndClearsSuccesses() async {
    let service = DefaultApplicationServiceFake()
    let model = makeModel(service: service)
    model.toggleSelection(for: .jpeg)
    model.toggleSelection(for: .png)

    await model.applySelectedFormats()

    XCTAssertEqual(service.setTypes, [.jpeg, .png])
    XCTAssertTrue(model.selectedFormats.isEmpty)
    XCTAssertEqual(model.summary, .success(count: 2))
}

func testPartialFailureKeepsOnlyFailedFormatSelected() async {
    let service = DefaultApplicationServiceFake(failingTypes: [.png])
    let model = makeModel(service: service)
    model.toggleSelection(for: .jpeg)
    model.toggleSelection(for: .png)

    await model.applySelectedFormats()

    XCTAssertEqual(model.selectedFormats, [.png])
    XCTAssertEqual(model.summary, .partialSuccess(succeeded: 1, failed: 1))
    XCTAssertNotNil(model.rows[.png]?.errorDescription)
}

func testInvalidApplicationBundlePreventsMutation() async {
    let service = DefaultApplicationServiceFake()
    let model = makeModel(service: service, appURL: nil)
    model.toggleSelection(for: .gif)

    await model.applySelectedFormats()

    XCTAssertTrue(service.setTypes.isEmpty)
    XCTAssertEqual(model.summary, .invalidApplicationBundle)
    XCTAssertEqual(model.selectedFormats, [.gif])
}
```

Use this fake and helper in the test file:

```swift
@MainActor
private final class DefaultApplicationServiceFake: DefaultApplicationServicing {
    var defaults: [UTType: URL]
    var failingTypes: Set<UTType>
    var setTypes: [UTType] = []

    init(defaults: [UTType: URL] = [:], failingTypes: Set<UTType> = []) {
        self.defaults = defaults
        self.failingTypes = failingTypes
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        defaults[contentType]
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        setTypes.append(contentType)
        if failingTypes.contains(contentType) { throw TestFailure.denied }
        defaults[contentType] = applicationURL
    }
}

private enum TestFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Denied" }
}

private func makeModel(
    service: DefaultApplicationServicing = DefaultApplicationServiceFake(),
    appURL: URL? = URL(fileURLWithPath: "/Applications/ImageView.app")
) -> FileAssociationSettingsModel {
    FileAssociationSettingsModel(service: service, applicationURL: { appURL })
}
```

- [ ] **Step 3: Run model tests and confirm the expected failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter FileAssociationSettingsModelTests
```

Expected: compilation fails because `FileAssociationSettingsModel`, row state, and summaries do not exist.

- [ ] **Step 4: Add explicit hashability and implement focused model orchestration**

Change the existing declaration in `SupportedImageFormat.swift` to:

```swift
public enum SupportedImageFormat: String, CaseIterable, Sendable, Hashable {
```

Create `FileAssociationSettingsModel.swift` with these exact public-to-module types and behaviors:

```swift
import Foundation
import ImageViewCore
import UniformTypeIdentifiers

struct FileAssociationRowState: Equatable {
    var defaultApplicationName: String?
    var isImageViewDefault = false
    var errorDescription: String?
}

enum FileAssociationSummary: Equatable {
    case success(count: Int)
    case partialSuccess(succeeded: Int, failed: Int)
    case failure(count: Int)
    case invalidApplicationBundle
}

@MainActor
final class FileAssociationSettingsModel: ObservableObject {
    static let commonFormats: [SupportedImageFormat] = [.jpeg, .png, .gif, .webp, .heic]
    static let allFormats: [SupportedImageFormat] = [
        .jpeg, .png, .gif, .webp, .heic,
        .tiff, .bmp, .heif, .avif, .svg
    ]

    @Published private(set) var selectedFormats: Set<SupportedImageFormat> = []
    @Published private(set) var rows: [SupportedImageFormat: FileAssociationRowState] = [:]
    @Published private(set) var showsAllFormats = false
    @Published private(set) var isApplying = false
    @Published private(set) var summary: FileAssociationSummary?

    var visibleFormats: [SupportedImageFormat] {
        showsAllFormats ? Self.allFormats : Self.commonFormats
    }

    var canApply: Bool { !selectedFormats.isEmpty && !isApplying }

    private let service: DefaultApplicationServicing
    private let applicationURL: () -> URL?

    init(
        service: DefaultApplicationServicing,
        applicationURL: @escaping () -> URL?
    ) {
        self.service = service
        self.applicationURL = applicationURL
    }

    func toggleSelection(for format: SupportedImageFormat) {
        if selectedFormats.contains(format) {
            selectedFormats.remove(format)
        } else {
            selectedFormats.insert(format)
        }
        summary = nil
    }

    func selectCommonFormats() {
        selectedFormats.formUnion(Self.commonFormats)
        summary = nil
    }

    func setShowsAllFormats(_ showsAll: Bool) {
        showsAllFormats = showsAll
    }

    func refreshStatuses() {
        let imageViewURL = applicationURL()?.standardizedFileURL
        for format in Self.allFormats {
            guard let contentType = format.contentType else {
                rows[format] = FileAssociationRowState()
                continue
            }
            let defaultURL = service.defaultApplicationURL(for: contentType)?.standardizedFileURL
            rows[format] = FileAssociationRowState(
                defaultApplicationName: defaultURL?.deletingPathExtension().lastPathComponent,
                isImageViewDefault: defaultURL == imageViewURL,
                errorDescription: rows[format]?.errorDescription
            )
        }
    }

    func applySelectedFormats() async {
        guard canApply else { return }
        guard let appURL = applicationURL(), appURL.pathExtension.lowercased() == "app" else {
            summary = .invalidApplicationBundle
            return
        }

        isApplying = true
        summary = nil
        var succeeded = 0
        var failed = 0
        let formats = Self.allFormats.filter(selectedFormats.contains)

        for format in formats {
            guard let contentType = format.contentType else {
                failed += 1
                rows[format, default: FileAssociationRowState()].errorDescription = "Unsupported content type"
                continue
            }
            do {
                try await service.setDefaultApplication(at: appURL, for: contentType)
                succeeded += 1
                selectedFormats.remove(format)
                rows[format, default: FileAssociationRowState()].errorDescription = nil
            } catch {
                failed += 1
                rows[format, default: FileAssociationRowState()].errorDescription = error.localizedDescription
            }
        }

        isApplying = false
        summary = failed == 0
            ? .success(count: succeeded)
            : succeeded == 0
                ? .failure(count: failed)
                : .partialSuccess(succeeded: succeeded, failed: failed)
        refreshStatuses()
    }
}
```

Use module-internal access rather than making these types public.

- [ ] **Step 5: Run model and service tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'DefaultApplicationServiceTests|FileAssociationSettingsModelTests'
```

Expected: all focused tests pass with zero failures.

- [ ] **Step 6: Commit the model**

```bash
git add Sources/ImageViewCore/Models/SupportedImageFormat.swift Sources/ImageViewApp/Settings/FileAssociationSettingsModel.swift Tests/ImageViewAppTests/FileAssociationSettingsModelTests.swift
git commit -m "feat: model image file associations"
```

---

### Task 3: Render and Localize the File-Association Settings UI

**Files:**
- Modify: `Sources/ImageViewApp/Settings/PreferencesWindowController.swift`
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/ImageViewAppTests/PreferencesWindowControllerTests.swift`
- Modify: `Tests/ImageViewAppTests/AppStringsTests.swift`

**Interfaces:**
- Consumes: `FileAssociationSettingsModel`, `DefaultApplicationServicing`, existing `AppSettings`, and `AppStrings.text(_:preferredLanguages:)`.
- Produces: `PreferencesWindowController.init(settings:defaultApplicationService:applicationURL:preferredLanguages:)` and an accessible native AppKit file-association section.

- [ ] **Step 1: Add failing localization tests**

Extend `AppStringsTests` with representative English and Chinese assertions:

```swift
func testFileAssociationSettingsLocalizeInEnglishAndSimplifiedChinese() {
    XCTAssertEqual(AppStrings.text("settings.fileAssociations.title", preferredLanguages: ["en"]), "File Associations")
    XCTAssertEqual(AppStrings.text("settings.fileAssociations.apply", preferredLanguages: ["en"]), "Set ImageView as Default")
    XCTAssertEqual(AppStrings.text("settings.fileAssociations.title", preferredLanguages: ["zh-Hans"]), "文件关联")
    XCTAssertEqual(AppStrings.text("settings.fileAssociations.apply", preferredLanguages: ["zh-Hans"]), "将 ImageView 设为默认")
}
```

- [ ] **Step 2: Add failing controller tests**

Create `PreferencesWindowControllerTests.swift` with an injected fake service and inspectable accessibility identifiers:

```swift
import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewApp

@MainActor
final class PreferencesWindowControllerTests: XCTestCase {
    func testSettingsWindowContainsCommonFormatsAndCollapsedExtras() throws {
        let controller = makeController(preferredLanguages: ["en"])
        let content = try XCTUnwrap(controller.window?.contentView)

        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.jpeg"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.png"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.gif"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.webp"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.heic"))
        XCTAssertNil(content.viewWithIdentifier("fileAssociation.svg"))
    }

    func testApplyButtonStartsDisabled() throws {
        let controller = makeController(preferredLanguages: ["en"])
        let button = try XCTUnwrap(
            controller.window?.contentView?.viewWithIdentifier("fileAssociation.apply") as? NSButton
        )
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.title, "Set ImageView as Default")
    }

    func testChineseSettingsUseLocalizedFileAssociationCopy() throws {
        let controller = makeController(preferredLanguages: ["zh-Hans"])
        let title = try XCTUnwrap(
            controller.window?.contentView?.viewWithIdentifier("fileAssociation.title") as? NSTextField
        )
        XCTAssertEqual(title.stringValue, "文件关联")
    }
}
```

Add a file-private `NSView` recursive lookup helper because AppKit's identifier lookup is not recursive by default:

```swift
private extension NSView {
    func viewWithIdentifier(_ rawValue: String) -> NSView? {
        if identifier?.rawValue == rawValue { return self }
        return subviews.lazy.compactMap { $0.viewWithIdentifier(rawValue) }.first
    }
}
```

Add this test helper and fake:

```swift
private func makeController(preferredLanguages: [String]) -> PreferencesWindowController {
    let suiteName = "PreferencesWindowControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PreferencesWindowController(
        settings: AppSettings(defaults: defaults),
        defaultApplicationService: ControllerServiceFake(),
        applicationURL: { URL(fileURLWithPath: "/Applications/ImageView.app") },
        preferredLanguages: preferredLanguages
    )
}

@MainActor
private final class ControllerServiceFake: DefaultApplicationServicing {
    func defaultApplicationURL(for contentType: UTType) -> URL? { nil }
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {}
}
```

- [ ] **Step 3: Run the localization and controller tests to confirm failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'AppStringsTests|PreferencesWindowControllerTests'
```

Expected: localization assertions fail with untranslated keys and controller tests fail because the new initializer and controls do not exist.

- [ ] **Step 4: Add exact English and Simplified Chinese keys**

Register these keys in `AppStrings` and add them to both `.strings` files:

```text
settings.title
settings.general.title
settings.fileAssociations.title
settings.fileAssociations.selectCommon
settings.fileAssociations.showAll
settings.fileAssociations.showLess
settings.fileAssociations.apply
settings.fileAssociations.applying
settings.fileAssociations.defaultImageView
settings.fileAssociations.defaultOther
settings.fileAssociations.defaultUnknown
settings.fileAssociations.success
settings.fileAssociations.partialSuccess
settings.fileAssociations.failure
settings.fileAssociations.invalidBundle
settings.fileAssociations.unsupportedType
settings.format.jpeg
settings.format.png
settings.format.gif
settings.format.webp
settings.format.heic
settings.format.tiff
settings.format.bmp
settings.format.heif
settings.format.avif
settings.format.svg
```

English values:

```strings
"settings.title" = "ImageView Settings";
"settings.general.title" = "General";
"settings.fileAssociations.title" = "File Associations";
"settings.fileAssociations.selectCommon" = "Select Common Formats";
"settings.fileAssociations.showAll" = "Show All Formats";
"settings.fileAssociations.showLess" = "Show Fewer Formats";
"settings.fileAssociations.apply" = "Set ImageView as Default";
"settings.fileAssociations.applying" = "Setting defaults…";
"settings.fileAssociations.defaultImageView" = "Default: ImageView";
"settings.fileAssociations.defaultOther" = "Default: %@";
"settings.fileAssociations.defaultUnknown" = "Default application unknown";
"settings.fileAssociations.success" = "ImageView is now the default for %d formats.";
"settings.fileAssociations.partialSuccess" = "Set %d formats; %d failed.";
"settings.fileAssociations.failure" = "%d formats failed. Select them and try again.";
"settings.fileAssociations.invalidBundle" = "Launch ImageView from ImageView.app and try again.";
"settings.fileAssociations.unsupportedType" = "Unsupported content type";
```

Simplified Chinese values:

```strings
"settings.title" = "ImageView 设置";
"settings.general.title" = "通用";
"settings.fileAssociations.title" = "文件关联";
"settings.fileAssociations.selectCommon" = "选择常用格式";
"settings.fileAssociations.showAll" = "显示全部格式";
"settings.fileAssociations.showLess" = "收起其他格式";
"settings.fileAssociations.apply" = "将 ImageView 设为默认";
"settings.fileAssociations.applying" = "正在设置默认应用…";
"settings.fileAssociations.defaultImageView" = "默认：ImageView";
"settings.fileAssociations.defaultOther" = "默认：%@";
"settings.fileAssociations.defaultUnknown" = "默认应用未知";
"settings.fileAssociations.success" = "已将 ImageView 设为 %d 种格式的默认应用。";
"settings.fileAssociations.partialSuccess" = "已设置 %d 种格式，%d 种失败。";
"settings.fileAssociations.failure" = "%d 种格式设置失败，请保持勾选并重试。";
"settings.fileAssociations.invalidBundle" = "请从 ImageView.app 启动后重试。";
"settings.fileAssociations.unsupportedType" = "不支持的内容类型";
```

Format values use their uppercase names in both languages. Include extension labels in controller metadata: `JPG, JPEG`; `PNG`; `GIF`; `WEBP`; `HEIC`; `TIF, TIFF`; `BMP`; `HEIF`; `AVIF`; `SVG`.

- [ ] **Step 5: Build the native AppKit section and bind it to model state**

Refactor `PreferencesWindowController` without moving unrelated settings behavior:

- Change the window content size to `560 × 620` points, keep `.titled` and `.closable`, and set its localized title.
- Wrap the existing four checkboxes under a localized **General** heading.
- Add a separator and localized **File Associations** heading.
- Build rows from `model.visibleFormats`; each row is an `NSButton` checkbox plus name/extension/status text fields.
- Assign identifiers `fileAssociation.<rawValue>` to row containers, `fileAssociation.title` to the section title, and `fileAssociation.apply` to the apply button.
- Rebuild only the rows stack when show-all state changes. Preserve state in the model.
- Set checkbox target/action through `representedObject = format.rawValue` and `SupportedImageFormat(rawValue:)`.
- On `showWindow`, call `model.refreshStatuses()` and render.
- On apply, start `Task { await model.applySelectedFormats(); render() }`.
- While `model.isApplying`, disable all mutation controls and display the localized applying title.
- Format summaries with `String(format:locale:arguments:)` from localized format strings.
- Render per-row errors in `NSColor.systemRed`; normal status uses `NSColor.secondaryLabelColor`.

Use this initializer so production and tests share the same path:

```swift
init(
    settings: AppSettings = .shared,
    defaultApplicationService: DefaultApplicationServicing = WorkspaceDefaultApplicationService(),
    applicationURL: @escaping () -> URL? = { Bundle.main.bundleURL },
    preferredLanguages: [String] = Locale.preferredLanguages
) {
    self.settings = settings
    self.preferredLanguages = preferredLanguages
    self.fileAssociationModel = FileAssociationSettingsModel(
        service: defaultApplicationService,
        applicationURL: applicationURL
    )
    // Create the window, call super.init(window:), then setup().
}
```

Update `AppDelegate` to own one production service and pass it to the settings controller:

```swift
private let defaultApplicationService: DefaultApplicationServicing

init(
    settings: AppSettings = .shared,
    defaultApplicationService: DefaultApplicationServicing = WorkspaceDefaultApplicationService()
) {
    self.settings = settings
    self.defaultApplicationService = defaultApplicationService
    super.init()
}
```

Do not add a File-menu entry and do not persist selection in `AppSettings`.

- [ ] **Step 6: Run UI, localization, model, and service tests**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox --filter 'AppStringsTests|PreferencesWindowControllerTests|FileAssociationSettingsModelTests|DefaultApplicationServiceTests'
```

Expected: all focused tests pass with zero failures.

- [ ] **Step 7: Run complete verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache swift test --disable-sandbox
```

Expected: the full suite passes with zero failures.

Run:

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_CACHE_PATH=$PWD/.build/swiftpm-cache scripts/build-app.sh
```

Expected: Release build succeeds and produces `/Users/gaoyinrui/Documents/Codex/ImageView/.build/ImageView.app` with the existing document-type declarations intact.

- [ ] **Step 8: Perform a manual smoke test from the built app**

Launch `.build/ImageView.app`, open **ImageView → Settings…**, and verify:

1. Five common formats appear initially and **Show All Formats** reveals five more.
2. **Set ImageView as Default** is disabled until at least one format is checked.
3. Choose one disposable test format, apply, accept any macOS consent prompt, and confirm the row becomes **Default: ImageView**.
4. Confirm an unchecked format's displayed default application did not change.
5. Switch app appearance between light and dark and confirm the settings section remains legible.

This step intentionally changes only the single format explicitly selected by the tester.

- [ ] **Step 9: Commit the settings UI**

```bash
git add Sources/ImageViewApp/Settings/PreferencesWindowController.swift Sources/ImageViewApp/AppDelegate.swift Sources/ImageViewApp/Localization/AppStrings.swift Sources/ImageViewApp/Resources/en.lproj/Localizable.strings Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings Tests/ImageViewAppTests/PreferencesWindowControllerTests.swift Tests/ImageViewAppTests/AppStringsTests.swift
git commit -m "feat: add image file association settings"
```

---

## Completion Checklist

- [ ] `git status --short` shows no unintended files.
- [ ] Every selected format is processed once in documented order.
- [ ] No unchecked format reaches the setter.
- [ ] Successful selections clear; failed selections remain checked.
- [ ] Settings reopen refreshes default-application names.
- [ ] English and Simplified Chinese copy is complete.
- [ ] Full Swift tests and Release build pass.
- [ ] No legacy Launch Services setter or external utility was introduced.
