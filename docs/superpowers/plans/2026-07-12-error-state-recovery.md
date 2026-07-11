# Error-State Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unsupported files from being selected in the open panel and provide a complete recovery loop when an image still fails to open through drag, Finder, command line, or decoding.

**Architecture:** Keep file filtering in `AppDelegate`, error data in `ViewerViewModel`, and presentation/recovery routing in `MainWindowController`. Empty and error action views remain siblings of the gesture-enabled image canvas so their buttons receive normal mouse events.

**Tech Stack:** Swift 6, AppKit, Combine, UniformTypeIdentifiers, XCTest, Swift Package Manager.

---

### Task 1: Keep Actionable State Outside the Gesture Canvas

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift:169-181`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift:364`

- [ ] **Step 1: Write the failing ancestor-chain test**

```swift
func testEmptyStateOpenButtonHasNoGestureRecognizerInAncestorChain() throws {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    let contentView = try XCTUnwrap(controller.window?.contentView)
    func findOpenButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.title == "打开图片…" || button.title == "Open Image…" {
            return button
        }
        return view.subviews.lazy.compactMap(findOpenButton).first
    }
    let button = try XCTUnwrap(findOpenButton(in: contentView))

    var ancestor = button.superview
    while let view = ancestor {
        XCTAssertTrue(view.gestureRecognizers.isEmpty)
        ancestor = view.superview
    }
}
```

- [ ] **Step 2: Verify the test fails with the empty state under `ImageCanvasView`**

Run:

```bash
swift test --disable-sandbox --filter MainWindowControllerTests/testEmptyStateOpenButtonHasNoGestureRecognizerInAncestorChain
```

Expected: FAIL because `ImageCanvasView` owns click and magnification recognizers.

- [ ] **Step 3: Move the empty state beside the canvas**

```swift
rootView.addSubview(canvas)
rootView.addSubview(emptyStateView)
// Keep error-free display constraints relative to canvas.
```

- [ ] **Step 4: Verify the focused test passes**

Run the Step 2 command. Expected: 1 test, 0 failures.

### Task 2: Filter the Open Panel to Supported Formats

**Files:**
- Modify: `Sources/ImageViewApp/AppDelegate.swift:1-40`
- Test: `Tests/ImageViewAppTests/AppDelegateTests.swift`

- [ ] **Step 1: Write the failing open-panel configuration test**

```swift
func testOpenPanelAllowsOnlySupportedImageFormats() {
    let panel = NSOpenPanel()

    AppDelegate.configureOpenPanel(panel)

    let expected = Set(SupportedImageFormat.allCases.compactMap(\.contentType).map(\.identifier))
    XCTAssertEqual(Set(panel.allowedContentTypes.map(\.identifier)), expected)
    XCTAssertFalse(panel.allowsOtherFileTypes)
    XCTAssertFalse(panel.canChooseDirectories)
    XCTAssertTrue(panel.canChooseFiles)
    XCTAssertTrue(panel.allowsMultipleSelection)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --disable-sandbox --filter AppDelegateTests/testOpenPanelAllowsOnlySupportedImageFormats
```

Expected: compile failure because `configureOpenPanel` does not exist.

- [ ] **Step 3: Add the shared panel configuration**

```swift
import ImageViewCore

static func configureOpenPanel(_ panel: NSOpenPanel) {
    panel.allowedContentTypes = SupportedImageFormat.allCases.compactMap(\.contentType)
    panel.allowsOtherFileTypes = false
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
}
```

Call `Self.configureOpenPanel(panel)` in the production `chooseImageURLs` closure.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: 1 test, 0 failures.

### Task 3: Build the Error-State Component

**Files:**
- Create: `Sources/ImageViewApp/Viewer/ErrorStateView.swift`
- Delete: `Sources/ImageViewApp/Viewer/ErrorOverlayView.swift`
- Modify: `Sources/ImageViewApp/Localization/AppStrings.swift`
- Modify: `Sources/ImageViewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageViewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/ImageViewAppTests/ErrorStateViewTests.swift`

- [ ] **Step 1: Write failing localization and callback tests**

```swift
@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testDisplaysErrorAndLocalizedRetryButton() {
        let view = ErrorStateView(preferredLanguages: ["zh-Hans"])
        view.message = "不支持的图片格式：txt"
        XCTAssertEqual(view.messageForTesting, "不支持的图片格式：txt")
        XCTAssertEqual(view.buttonTitleForTesting, "重新选择图片…")
    }

    func testRetryButtonInvokesCallbackOnce() {
        let view = ErrorStateView(preferredLanguages: ["en"])
        var count = 0
        view.onRetryRequested = { count += 1 }
        view.performRetryForTesting()
        XCTAssertEqual(count, 1)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --disable-sandbox --filter ErrorStateViewTests
```

Expected: compile failure because `ErrorStateView` does not exist.

- [ ] **Step 3: Implement the focused view**

```swift
final class ErrorStateView: NSView {
    var onRetryRequested: (() -> Void)?
    private let messageLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton()

    var message: String {
        get { messageLabel.stringValue }
        set { messageLabel.stringValue = newValue }
    }

    @objc private func requestRetry(_ sender: Any?) {
        onRetryRequested?()
    }

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        super.init(frame: .zero)
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        retryButton.title = AppStrings.text("errorState.retry", preferredLanguages: preferredLanguages)
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(requestRetry(_:))

        let stack = NSStackView(views: [messageLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var messageForTesting: String { messageLabel.stringValue }
    var buttonTitleForTesting: String { retryButton.title }
    func performRetryForTesting() { requestRetry(nil) }
}
```

Add `errorState.retry` translations: `Choose Another Image…` and `重新选择图片…`.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Step 2 command. Expected: 2 tests, 0 failures.

### Task 4: Reset a Failed Viewer to an Empty Window

**Files:**
- Modify: `Sources/ImageViewApp/Viewer/ViewerViewModel.swift:150-180`
- Test: `Tests/ImageViewAppTests/ViewerViewModelTests.swift`

- [ ] **Step 1: Write the failing reset test**

```swift
func testResetToEmptyStateClearsFailedOpen() async {
    let viewModel = ViewerViewModel()
    await viewModel.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))

    viewModel.resetToEmptyState()

    XCTAssertEqual(viewModel.loadPhase, .empty)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertNil(viewModel.navigationState)
    XCTAssertNil(viewModel.currentImage)
    XCTAssertNil(viewModel.currentMetadata)
    XCTAssertEqual(viewModel.displayTitle, "ImageView")
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --disable-sandbox --filter ViewerViewModelTests/testResetToEmptyStateClearsFailedOpen
```

Expected: compile failure because `resetToEmptyState` does not exist.

- [ ] **Step 3: Implement the reset operation**

```swift
func resetToEmptyState() {
    _ = beginDisplayRequest()
    pendingOperations.removeAll()
    navigationState = nil
    currentImage = nil
    currentMetadata = nil
    persistedCurrentImage = nil
    displayedFileVersion = nil
    hasUnsavedEdits = false
    errorMessage = nil
    loadPhase = .empty
    updateDisplayTitle()
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: 1 test, 0 failures.

### Task 5: Wire Error Recovery and Cancel Semantics

**Files:**
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewApp/AppDelegate.swift`
- Modify: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`
- Modify: `Tests/ImageViewAppTests/AppDelegateTests.swift`

- [ ] **Step 1: Write failing controller tests**

```swift
func testErrorStateAppearsWithoutEmptyState() {
    XCTAssertTrue(MainWindowController.shouldDisplayErrorState(hasCurrentImage: false, hasError: true))
    XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
        hasCurrentImage: false,
        loadPhase: .failed,
        hasError: true
    ))
}

func testCancelledRetryResetsFailedWindowForReuse() async {
    let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
    controller.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))
    await Task.yield()

    controller.returnToEmptyStateAfterCancelledOpen()

    XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
    XCTAssertFalse(controller.hasAssignedOpenRequest)
}
```

- [ ] **Step 2: Write failing AppDelegate cancel-routing tests**

```swift
func testCancelledChooserReturnsFailedRequestingWindowToEmptyState() async {
    let harness = WindowHarness(chosenURLs: nil)
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()
    let controller = delegate.imageWindowControllersForTesting[0]
    controller.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))
    for _ in 0..<10 where !controller.isShowingRecoverableErrorForTesting {
        await Task.yield()
    }

    controller.onOpenRequested?()

    XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
    XCTAssertFalse(controller.hasAssignedOpenRequest)
}

func testCancelledChooserLeavesOrdinaryEmptyWindowUnchanged() {
    let harness = WindowHarness(chosenURLs: nil)
    let delegate = harness.makeDelegate()
    delegate.finishLaunchingForTesting()
    let controller = delegate.imageWindowControllersForTesting[0]

    controller.onOpenRequested?()

    XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
    XCTAssertFalse(controller.hasAssignedOpenRequest)
}
```

- [ ] **Step 3: Run focused tests and verify RED**

```bash
swift test --disable-sandbox --filter MainWindowControllerTests/testErrorStateAppearsWithoutEmptyState
swift test --disable-sandbox --filter MainWindowControllerTests/testCancelledRetryResetsFailedWindowForReuse
```

Expected: compile failures for missing error-state and reset APIs.

- [ ] **Step 4: Wire the error view in `MainWindowController`**

```swift
private let errorStateView = ErrorStateView()

errorStateView.onRetryRequested = { [weak self] in
    self?.onOpenRequested?()
}

func returnToEmptyStateAfterCancelledOpen() {
    guard viewModel.currentImage == nil, viewModel.errorMessage != nil else { return }
    viewModel.resetToEmptyState()
    hasAssignedOpenRequest = false
}

var isShowingRecoverableErrorForTesting: Bool {
    viewModel.currentImage == nil && viewModel.errorMessage != nil
}
```

Add `errorStateView` beside `canvas`, bind `viewModel.$errorMessage` to its message, and make the error state visible only when there is no current image and an error exists.

- [ ] **Step 5: Route the requesting controller through `AppDelegate`**

```swift
controller.onOpenRequested = { [weak self, weak controller] in
    self?.requestOpenImages(requesting: controller)
}

private func requestOpenImages(requesting controller: MainWindowController? = nil) {
    guard let urls = chooseImageURLs() else {
        controller?.returnToEmptyStateAfterCancelledOpen()
        return
    }
    guard !urls.isEmpty else { return }
    openURLs(urls)
}
```

The File menu calls `requestOpenImages(requesting: menuTargetImageController)`.

- [ ] **Step 6: Run all focused tests and verify GREEN**

```bash
swift test --disable-sandbox --filter ErrorStateViewTests
swift test --disable-sandbox --filter MainWindowControllerTests
swift test --disable-sandbox --filter AppDelegateTests
swift test --disable-sandbox --filter ViewerViewModelTests
```

Expected: all selected suites pass with 0 failures.

### Task 6: Full Verification and Delivery

**Files:**
- Verify all modified production and test files.

- [ ] **Step 1: Run the full test suite**

```bash
swift test --disable-sandbox
```

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Build and install the app**

```bash
scripts/install-app.sh
codesign --verify --deep --strict --verbose=2 /Applications/ImageView.app
```

Expected: Release build succeeds and the installed bundle satisfies its designated requirement.

- [ ] **Step 3: Perform end-to-end UI checks**

- Open panel: `.photoslibrary` and `.txt` are disabled.
- Empty state: coordinate-level click opens the panel.
- Error state: retry button opens the panel.
- Error retry cancellation: returns to normal empty state.
- `Command-O`: opens the panel from empty, error, and image states.
- Dragging an invalid file shows recoverable error; dragging a valid image recovers.

- [ ] **Step 4: Run repository safety checks**

```bash
git diff --check
/Users/zhupin/.codex/hooks/secret-scan.sh .
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit and push**

```bash
git add Sources Tests docs/superpowers/plans/2026-07-12-error-state-recovery.md
git commit -m "fix: complete image-open recovery flow"
git push origin main
```
