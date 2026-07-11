# ImageView Actionable Empty State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ImageView's ambiguous blank startup canvas with a localized, accessible empty state that opens images through the existing multi-window pipeline and disappears for loading, image, and error states.

**Architecture:** Add an explicit `loading` phase to `ViewerViewModel`, a focused AppKit `EmptyStateView`, and a pure visibility rule owned by `MainWindowController`. `AppDelegate` remains the single owner of `NSOpenPanel`; both the File menu and the new button call one injected/testable open-panel path.

**Tech Stack:** Swift 6, AppKit, Combine, SwiftPM, XCTest, ImageIO-backed existing image pipeline.

---

## File map

- Create `Sources/ImageViewApp/Viewer/EmptyStateView.swift`: native icon, labels, button, localization, accessibility, and one open-request callback.
- Create `Tests/ImageViewAppTests/EmptyStateViewTests.swift`: component text and button-callback coverage.
- Modify `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`: add and publish an explicit `loading` phase; return to clean `empty` after removing the last image.
- Modify `Tests/ImageViewAppTests/ViewerViewModelTests.swift`: prove opening enters `loading` immediately and last-item removal returns to a non-error empty state.
- Modify `Sources/ImageViewApp/MainWindowController.swift`: place the empty-state view, calculate its visibility, hide image-only status content, and forward the open request.
- Modify `Tests/ImageViewAppTests/MainWindowControllerTests.swift`: prove the visibility truth table, initial rendered state, and callback forwarding.
- Modify `Sources/ImageViewApp/AppDelegate.swift`: share one open-panel path between the menu and each window's empty-state button.
- Modify `Tests/ImageViewAppTests/AppDelegateTests.swift`: prove the button uses the existing ordered multi-URL pipeline and cancellation is a no-op.
- Modify `Sources/ImageViewApp/Localization/AppStrings.swift`: declare the empty-state localization key set.
- Modify `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`: English empty-state text.
- Modify `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`: Simplified Chinese empty-state text.
- Modify `Tests/ImageViewAppTests/AppStringsTests.swift`: verify both localizations are complete.

### Task 1: Make loading distinct from a truly empty window

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Add failing loading and last-item tests**

Add a suspended full-image loader and assert that `open(url:)` publishes `loading` before any image result:

```swift
func testOpenPublishesLoadingBeforeAnyDecodedImage() async throws {
    let url = URL(fileURLWithPath: "/tmp/loading.png")
    let image = makeDecodedImage(width: 8, height: 6)
    let previewLoader = ControlledImageLoader(images: [url: image])
    let fullLoader = ControlledImageLoader(images: [url: image])
    let viewModel = ViewerViewModel(
        scanContainingDirectory: { _ in [] },
        loadImageAtURL: fullLoader.load(url:format:),
        loadPreviewAtURL: previewLoader.load(url:format:)
    )
    await previewLoader.pauseNextLoad(for: url)
    await fullLoader.pauseNextLoad(for: url)

    let task = Task { await viewModel.open(url: url) }
    await previewLoader.waitUntilPaused(url: url)
    await fullLoader.waitUntilPaused(url: url)

    XCTAssertEqual(viewModel.loadPhase, .loading)
    XCTAssertNil(viewModel.currentImage)

    try await fullLoader.resume(url: url)
    try await previewLoader.resume(url: url)
    await task.value
    XCTAssertEqual(viewModel.loadPhase, .full)
}
```

Update the existing last-item trash test so the terminal assertions are:

```swift
XCTAssertNil(viewModel.currentImage)
XCTAssertNil(viewModel.navigationState)
XCTAssertEqual(viewModel.loadPhase, .empty)
XCTAssertNil(viewModel.errorMessage)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter ViewerViewModelTests/testOpenPublishesLoadingBeforeAnyDecodedImage
swift test --disable-sandbox --filter ViewerViewModelTests/testMoveCurrentToTrashClearsDisplayedImageWhenLastItemIsRemoved
```

Expected: the first test does not compile because `.loading` is absent; after only adding the case, both tests fail because opening still publishes `.empty` and last-item removal still publishes `没有可显示的图片`.

- [ ] **Step 3: Implement the minimal phase transitions**

Extend the phase enum:

```swift
enum ImageLoadPhase: Equatable {
    case empty
    case loading
    case preview
    case full
    case failed
}
```

In `open(url:)`, assign `.loading` immediately after clearing the prior request state and before format validation. In `startDisplayCurrentAndPreload()` and external-file refresh, assign `.loading` before asynchronous decode. When the last item is deliberately moved to Trash, keep `.empty` and set `errorMessage = nil`; external deletion continues to use the existing explicit error.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter ViewerViewModelTests
```

Expected: all `ViewerViewModelTests` pass, including progressive-loading race and edit-safety coverage.

- [ ] **Step 5: Commit the state-model change**

```bash
git add Sources/ImageViewApp/Viewer/ViewerViewModel.swift Tests/ImageViewAppTests/ViewerViewModelTests.swift
git commit -m "fix: distinguish loading from empty state"
```

### Task 2: Build the localized native empty-state component

**Files:**
- Create: `Sources/ImageViewApp/Viewer/EmptyStateView.swift`
- Create: `Tests/ImageViewAppTests/EmptyStateViewTests.swift`
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ImageViewAppTests/AppStringsTests.swift`

- [ ] **Step 1: Add failing localization and component tests**

Add `AppStrings.emptyStateKeys` coverage:

```swift
func testEveryEmptyStateLabelHasChineseAndEnglishTranslations() {
    for key in AppStrings.emptyStateKeys {
        XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
        XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
    }
}
```

Create `EmptyStateViewTests`:

```swift
@MainActor
final class EmptyStateViewTests: XCTestCase {
    func testLocalizesEnglishAndSimplifiedChineseContent() {
        let english = EmptyStateView(preferredLanguages: ["en"])
        XCTAssertEqual(english.titleTextForTesting, "Open an Image")
        XCTAssertEqual(english.messageTextForTesting, "Drag an image here, or choose one below")
        XCTAssertEqual(english.buttonTitleForTesting, "Open Image…")

        let chinese = EmptyStateView(preferredLanguages: ["zh-Hans"])
        XCTAssertEqual(chinese.titleTextForTesting, "打开图片")
        XCTAssertEqual(chinese.messageTextForTesting, "将图片拖到这里，或点击下方按钮")
        XCTAssertEqual(chinese.buttonTitleForTesting, "打开图片…")
    }

    func testOpenButtonInvokesCallbackExactlyOnce() {
        let view = EmptyStateView(preferredLanguages: ["en"])
        var count = 0
        view.onOpenRequested = { count += 1 }

        view.performOpenForTesting()

        XCTAssertEqual(count, 1)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter AppStringsTests/testEveryEmptyStateLabelHasChineseAndEnglishTranslations
swift test --disable-sandbox --filter EmptyStateViewTests
```

Expected: compile failures because `emptyStateKeys` and `EmptyStateView` do not exist.

- [ ] **Step 3: Add localization keys and the focused AppKit component**

Declare:

```swift
static let emptyStateKeys = [
    "emptyState.title",
    "emptyState.message",
    "emptyState.open"
]
```

Add these string entries:

```text
"emptyState.title" = "Open an Image";
"emptyState.message" = "Drag an image here, or choose one below";
"emptyState.open" = "Open Image…";
```

```text
"emptyState.title" = "打开图片";
"emptyState.message" = "将图片拖到这里，或点击下方按钮";
"emptyState.open" = "打开图片…";
```

Implement `EmptyStateView` as an `NSView` containing an `NSImageView`, two label-style `NSTextField`s, an `NSButton`, and a vertical `NSStackView`. Use `photo.on.rectangle.angled`, system label colors and standard button styling. Set `setAccessibilityElement(false)` on the decorative icon, use localized text for the remaining accessibility labels, and expose only the three read-only test strings plus `performOpenForTesting()`.

The action must be exactly:

```swift
@objc private func requestOpen(_ sender: Any?) {
    onOpenRequested?()
}

func performOpenForTesting() {
    requestOpen(nil)
}
```

- [ ] **Step 4: Run component and localization tests and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter EmptyStateViewTests
swift test --disable-sandbox --filter AppStringsTests
```

Expected: all selected tests pass in English and Simplified Chinese.

- [ ] **Step 5: Commit the component**

```bash
git add Sources/ImageViewApp/Viewer/EmptyStateView.swift Sources/ImageViewApp/Localization/AppStrings.swift Sources/ImageViewApp/Resources/en.lproj/Localizable.strings Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings Tests/ImageViewAppTests/EmptyStateViewTests.swift Tests/ImageViewAppTests/AppStringsTests.swift
git commit -m "feat: add localized image empty state"
```

### Task 3: Integrate visibility, status content, and the shared open pipeline

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`
- Test: `Tests/ImageViewAppTests/AppDelegateTests.swift`

- [ ] **Step 1: Add failing controller and delegate tests**

Add the pure visibility truth table:

```swift
func testEmptyStateOnlyAppearsForARealNonErrorEmptyWindow() {
    XCTAssertTrue(MainWindowController.shouldDisplayEmptyState(
        hasCurrentImage: false, loadPhase: .empty, hasError: false
    ))
    for phase in [ImageLoadPhase.loading, .preview, .full, .failed] {
        XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: false, loadPhase: phase, hasError: false
        ))
    }
    XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
        hasCurrentImage: true, loadPhase: .empty, hasError: false
    ))
    XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
        hasCurrentImage: false, loadPhase: .empty, hasError: true
    ))
}

func testNewWindowShowsEmptyStateAndHidesImageOnlyStatus() {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
    XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
}

func testEmptyStateOpenRequestIsForwarded() {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    var requestCount = 0
    controller.onOpenRequested = { requestCount += 1 }
    controller.requestOpenFromEmptyStateForTesting()
    XCTAssertEqual(requestCount, 1)
}
```

Extend the AppDelegate harness with an injected `chooseImageURLs` result and add:

```swift
func testEmptyStateOpenRequestUsesExistingMultiURLPipeline() {
    let urls = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")]
    let harness = WindowHarness(chosenURLs: urls)
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()

    delegate.imageWindowControllersForTesting[0].onOpenRequested?()

    XCTAssertEqual(harness.openRequests, urls)
    XCTAssertEqual(delegate.imageWindowCount, 2)
}

func testCancelledEmptyStateOpenRequestDoesNothing() {
    let harness = WindowHarness(chosenURLs: nil)
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()

    delegate.imageWindowControllersForTesting[0].onOpenRequested?()

    XCTAssertTrue(harness.openRequests.isEmpty)
    XCTAssertEqual(delegate.imageWindowCount, 1)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter MainWindowControllerTests/testEmptyState
swift test --disable-sandbox --filter MainWindowControllerTests/testNewWindowShowsEmptyStateAndHidesImageOnlyStatus
swift test --disable-sandbox --filter AppDelegateTests/testEmptyStateOpenRequestUsesExistingMultiURLPipeline
```

Expected: compile failures for missing controller properties, visibility function, callback, and delegate chooser seam.

- [ ] **Step 3: Integrate `EmptyStateView` in the main window**

Add:

```swift
var onOpenRequested: (() -> Void)?
private let emptyStateView = EmptyStateView()
```

Place `emptyStateView` in `canvas`, above the image and below the existing error overlay, constrain it to the canvas center, and forward `emptyStateView.onOpenRequested` to the controller callback.

Call one update method from the existing `currentImage` and `errorMessage` subscriptions plus a new `loadPhase` subscription:

```swift
private func updateEmptyStatePresentation() {
    let hasCurrentImage = viewModel.currentImage != nil
    emptyStateView.isHidden = !Self.shouldDisplayEmptyState(
        hasCurrentImage: hasCurrentImage,
        loadPhase: viewModel.loadPhase,
        hasError: viewModel.errorMessage != nil
    )
    for view in [bottomDimensionLabel, bottomPageLabel, bottomZoomLabel, bottomInfoButton] {
        view.isHidden = !hasCurrentImage
    }
}

static func shouldDisplayEmptyState(
    hasCurrentImage: Bool,
    loadPhase: ImageLoadPhase,
    hasError: Bool
) -> Bool {
    !hasCurrentImage && loadPhase == .empty && !hasError
}
```

Expose the three narrowly scoped testing accessors named in Step 1; do not expose the view model or mutable UI internals.

- [ ] **Step 4: Reuse one AppDelegate open-panel path**

Add an initializer dependency with the production default:

```swift
chooseImageURLs: @escaping () -> [URL]? = {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.urls : nil
}
```

Store it, add:

```swift
private func requestOpenImages() {
    guard let urls = chooseImageURLs(), !urls.isEmpty else { return }
    openURLs(urls)
}
```

Set `controller.onOpenRequested = { [weak self] in self?.requestOpenImages() }` in `createImageWindow()`, and reduce `openImage(_:)` to `requestOpenImages()`. Preserve the menu target, multi-selection ordering, empty startup-window reuse, later window creation, and recent-item callbacks.

- [ ] **Step 5: Run focused integration tests and verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter MainWindowControllerTests
swift test --disable-sandbox --filter AppDelegateTests
```

Expected: all controller and application lifecycle tests pass.

- [ ] **Step 6: Commit the integration**

```bash
git add Sources/ImageViewApp/MainWindowController.swift Sources/ImageViewApp/AppDelegate.swift Tests/ImageViewAppTests/MainWindowControllerTests.swift Tests/ImageViewAppTests/AppDelegateTests.swift
git commit -m "feat: make empty windows actionable"
```

### Task 4: Full verification, review, and GitHub delivery

**Files:**
- Verify all modified files from Tasks 1-3.
- Update `README.md` only if the final interaction differs from its existing “Finder, drag, or Open menu” description.

- [ ] **Step 1: Run all automated gates from a clean build**

Run:

```bash
swift package clean
swift test --disable-sandbox
scripts/build-app.sh
test -x .build/ImageView.app/Contents/MacOS/ImageView
plutil -lint .build/ImageView.app/Contents/Info.plist
test -f .build/ImageView.app/Contents/Resources/en.lproj/Localizable.strings
test -f .build/ImageView.app/Contents/Resources/zh-Hans.lproj/Localizable.strings
git diff --check main...HEAD
```

Expected: every command exits 0; the suite has no failures; the Release script prints `/Users/zhupin/Documents/git/ImageView/.build/ImageView.app`.

- [ ] **Step 2: Perform local UI smoke checks**

Launch the Release bundle and verify:

```bash
open -n .build/ImageView.app
```

Expected:

- Initial window shows the localized centered empty state and no image-only status values.
- Clicking “打开图片…” opens the same multi-select panel as `Command-O`.
- Cancelling keeps the empty state.
- Opening a valid image hides the empty state and restores status content.
- Dropping a valid image still works.
- Opening an invalid image shows only the existing error.
- Removing the final loaded image returns to the empty state.
- Dark and light appearances remain readable.

- [ ] **Step 3: Review the branch and fix any Critical or Important findings**

Inspect `git diff main...HEAD`, confirm every design acceptance criterion has code and test evidence, and rerun affected focused tests after any correction. Run the secret scan before publication:

```bash
/Users/zhupin/.codex/hooks/secret-scan.sh .
```

Expected: no secret patterns and no unresolved Critical or Important review finding.

- [ ] **Step 4: Fast-forward the verified work to `main` and push the original repository**

Run:

```bash
git fetch origin main
git rev-list --left-right --count origin/main...main
git switch main
git merge --ff-only codex/imageview-empty-state
git push origin main
```

Expected before the merge: `origin/main...main` reports `0 0`, proving the remote did not move and local `main` is still its direct base. Push the resulting fast-forward to `YuriGao/ImageView:main`. Do not force-push or rewrite history.

- [ ] **Step 5: Verify GitHub delivery**

Confirm `origin/main`, GitHub's `main` commit and local `HEAD` all resolve to the same SHA. Check whether GitHub Actions started; if the repository has no workflows, report that explicitly. Remove the merged feature branch after verification and report the GitHub commit URL plus local runnable app path.
