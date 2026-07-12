import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class MainWindowControllerTests: XCTestCase {
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

    func testBottomBarInfoControlUsesStandardInfoSymbol() {
        XCTAssertEqual(MainWindowController.bottomBarInfoSymbolName, "info.circle")
    }

    func testBottomBarStatusUsesCompactTrailingSpacing() {
        XCTAssertEqual(MainWindowController.bottomBarStatusToInfoSpacing, 8)
    }

    func testStatusBarFormatsDimensionsPageAndZoomIndependently() {
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/first.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/second.png"), format: .png)
        let state = NavigationState(items: [first, second], currentURL: second.url)

        XCTAssertEqual(
            MainWindowController.dimensionText(pixelWidth: 6000, pixelHeight: 4000),
            "6000 × 4000 px"
        )
        XCTAssertEqual(
            MainWindowController.dimensionText(pixelWidth: nil, pixelHeight: nil),
            "— × — px"
        )
        XCTAssertEqual(MainWindowController.pageText(navigationState: state), "2 / 2")
        XCTAssertEqual(MainWindowController.pageText(navigationState: nil), "0 / 0")
        XCTAssertEqual(MainWindowController.zoomText(zoomScale: 1.25), "125%")
    }

    func testCustomTitleBarHidesNativeWindowTitle() {
        let controller = MainWindowController()

        XCTAssertEqual(controller.window?.titleVisibility, .hidden)
    }

    func testDoubleClickTitleBarTogglesWindowZoom() throws {
        let controller = MainWindowController()
        let window = try XCTUnwrap(controller.window)
        let initialZoomState = window.isZoomed

        controller.toggleWindowZoom(nil)

        XCTAssertNotEqual(window.isZoomed, initialZoomState)
    }

    func testContentBarsReserveStableSpaceAroundCanvas() {
        XCTAssertEqual(MainWindowController.titleBarHeight, 32)
        XCTAssertEqual(MainWindowController.bottomBarHeight, 28)
    }

    func testShouldResetCanvasTransformOnlyWhenDisplayedItemChanges() {
        let first = URL(fileURLWithPath: "/tmp/first.png")
        let firstDuplicate = URL(fileURLWithPath: "/tmp/./first.png")
        let second = URL(fileURLWithPath: "/tmp/second.png")

        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: nil, to: first))
        XCTAssertFalse(MainWindowController.shouldResetCanvasTransform(from: first, to: firstDuplicate))
        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: first, to: second))
        XCTAssertTrue(MainWindowController.shouldResetCanvasTransform(from: first, to: nil))
        XCTAssertFalse(MainWindowController.shouldResetCanvasTransform(from: nil, to: nil))
    }

    func testKeyActionRoutesNavigationAndFullscreenKeys() {
        XCTAssertEqual(MainWindowController.keyAction(for: 123, shouldEndEditing: false), .showPrevious)
        XCTAssertEqual(MainWindowController.keyAction(for: 124, shouldEndEditing: false), .showNext)
        XCTAssertEqual(MainWindowController.keyAction(for: 51, shouldEndEditing: false), .moveToTrash)
        XCTAssertEqual(MainWindowController.keyAction(for: 49, shouldEndEditing: false), .toggleZoom)
        XCTAssertEqual(MainWindowController.keyAction(for: 36, shouldEndEditing: false), .toggleFullscreen)
        XCTAssertEqual(
            MainWindowController.keyAction(for: 13, shouldEndEditing: false, modifierFlags: [.command]),
            .closeWindow
        )
    }

    func testFolderBrowserModePassesThroughViewerOnlyKeyActions() {
        XCTAssertEqual(
            MainWindowController.keyAction(for: 123, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 124, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 51, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 49, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(
                for: 40,
                shouldEndEditing: false,
                modifierFlags: [.command],
                isFolderBrowserMode: true
            ),
            .passThrough
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 36, shouldEndEditing: false, isFolderBrowserMode: true),
            .passThrough
        )
    }

    func testMenuCommandMapsViewSelectors() {
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.showPreviousImage(_:))),
            .navigation
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.actualSize(_:))),
            .canvasSizing
        )
    }

    func testEscapeOnlyEndsEditingWhenDismissibleEditingStateExists() {
        XCTAssertEqual(MainWindowController.keyAction(for: 53, shouldEndEditing: true), .endEditing)
        XCTAssertEqual(MainWindowController.keyAction(for: 53, shouldEndEditing: false), .passThrough)
    }

    func testCropKeyActionsOverrideNormalWindowActionsWhileCropping() {
        XCTAssertEqual(
            MainWindowController.keyAction(
                for: 40,
                shouldEndEditing: false,
                isCropping: false,
                modifierFlags: [.command]
            ),
            .startCropping
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 36, shouldEndEditing: false, isCropping: true),
            .applyCrop
        )
        XCTAssertEqual(
            MainWindowController.keyAction(for: 53, shouldEndEditing: false, isCropping: true),
            .cancelCrop
        )
    }

    func testWindowActivationRequestsExternalFileRefresh() {
        XCTAssertTrue(MainWindowController.shouldRefreshCurrentFileOnWindowActivation())
    }

    func testExternalFileCheckIntervalStaysLightweight() {
        XCTAssertEqual(MainWindowController.externalFileCheckInterval, 2)
    }

    func testResolveUnsavedChangesProceedsOnlyForDiscardOrSuccessfulSave() {
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .save, saveSucceeded: true),
            .proceed
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .save, saveSucceeded: false),
            .stayOnCurrentImage
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .discard, saveSucceeded: false),
            .proceed
        )
        XCTAssertEqual(
            MainWindowController.resolveUnsavedChanges(choice: .cancel, saveSucceeded: false),
            .stayOnCurrentImage
        )
    }

    func testMenuCommandMapsEditSelectorsToExpectedOperations() {
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.startCropping(_:))),
            .startCropping
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.rotateClockwise(_:))),
            .editOperation(.rotateClockwise)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.rotateCounterClockwise(_:))),
            .editOperation(.rotateCounterClockwise)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.mirrorHorizontal(_:))),
            .editOperation(.mirrorHorizontal)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.mirrorVertical(_:))),
            .editOperation(.mirrorVertical)
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.saveEdits(_:))),
            .saveEdits
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.saveEditsAs(_:))),
            .saveEditsAs
        )
        XCTAssertEqual(
            MainWindowController.menuCommand(for: #selector(MainWindowController.discardEdits(_:))),
            .discardEdits
        )
    }

    func testMenuCommandAvailabilityRequiresFullImageForEditingButKeepsPreviewViewingAvailable() {
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: false,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.rotateClockwise),
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.mirrorHorizontal),
                hasCurrentItem: false,
                hasCurrentImage: true,
                canEditCurrentImage: true,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .saveEdits,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: true
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .saveEditsAs,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: true
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .saveEditsAs,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: true,
                hasUnsavedEdits: true
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .canvasSizing,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .navigation,
                hasCurrentItem: true,
                hasCurrentImage: true,
                canEditCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
    }

    func testFolderBrowserModeDisablesViewerOnlyMenuCommands() {
        let viewerOnlyCommands: [MainWindowController.MenuCommand] = [
            .fileOperationRequiringCurrentItem,
            .navigation,
            .canvasSizing,
            .startCropping,
            .editOperation(.rotateClockwise),
            .saveEdits,
            .saveEditsAs,
            .discardEdits
        ]

        for command in viewerOnlyCommands {
            XCTAssertFalse(
                MainWindowController.isMenuCommandEnabled(
                    command,
                    hasCurrentItem: true,
                    hasCurrentImage: true,
                    canEditCurrentImage: true,
                    hasUnsavedEdits: true,
                    isFolderBrowserMode: true
                ),
                "\(command) should be disabled while the folder browser owns the canvas"
            )
        }
    }

    func testValidateMenuItemDisablesHiddenViewerCommandsInFolderMode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where !controller.hasLoadedImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.hasLoadedImageForTesting)
        controller.openFolderForTesting(root, items: [ImageItem(url: imageURL, format: .png)])

        let rename = NSMenuItem(title: "Rename", action: #selector(MainWindowController.renameCurrentImage(_:)), keyEquivalent: "")
        let reveal = NSMenuItem(title: "Reveal", action: #selector(MainWindowController.revealCurrentImageInFinder(_:)), keyEquivalent: "")
        let trash = NSMenuItem(title: "Trash", action: #selector(MainWindowController.moveCurrentImageToTrash(_:)), keyEquivalent: "")
        let rotate = NSMenuItem(title: "Rotate", action: #selector(MainWindowController.rotateClockwise(_:)), keyEquivalent: "")
        let crop = NSMenuItem(title: "Crop", action: #selector(MainWindowController.startCropping(_:)), keyEquivalent: "")
        let zoom = NSMenuItem(title: "Zoom", action: #selector(MainWindowController.zoomToFit(_:)), keyEquivalent: "")

        for item in [rename, reveal, trash, rotate, crop, zoom] {
            XCTAssertFalse(controller.validateMenuItem(item), "\(item.title) should not target the hidden viewer")
        }
    }

    func testCanvasBackgroundAlwaysUsesSystemAppearance() {
        XCTAssertEqual(MainWindowController.canvasBackgroundColor(), .windowBackgroundColor)
    }

    func testEmptyStateOnlyAppearsForARealNonErrorEmptyWindow() {
        XCTAssertTrue(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: false,
            loadPhase: .empty,
            hasError: false
        ))

        for phase in [ImageLoadPhase.loading, .preview, .full, .failed] {
            XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
                hasCurrentImage: false,
                loadPhase: phase,
                hasError: false
            ))
        }

        XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: true,
            loadPhase: .empty,
            hasError: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayEmptyState(
            hasCurrentImage: false,
            loadPhase: .empty,
            hasError: true
        ))
    }

    func testNewWindowShowsEmptyStateAndHidesImageOnlyStatus() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
        XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
    }

    func testImageStatusContentOnlyAppearsWhenAnImageExists() {
        XCTAssertTrue(MainWindowController.shouldHideImageStatusContent(hasCurrentImage: false))
        XCTAssertFalse(MainWindowController.shouldHideImageStatusContent(hasCurrentImage: true))
    }

    func testInspectorRequiresBothTheSettingAndAnImage() {
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: false,
            hasCurrentImage: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: true,
            hasCurrentImage: false
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayInspector(
            isEnabled: false,
            hasCurrentImage: true
        ))
        XCTAssertTrue(MainWindowController.shouldDisplayInspector(
            isEnabled: true,
            hasCurrentImage: true
        ))
    }

    func testNewEmptyWindowHidesPreviouslyEnabledInspector() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.showsInspector = true

        let controller = MainWindowController(settings: settings)

        XCTAssertFalse(controller.isInspectorVisibleForTesting)
    }

    func testEmptyStateOpenRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onOpenRequested = { requestCount += 1 }

        controller.requestOpenFromEmptyStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testEmptyStateBrowseFolderRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onBrowseFolderRequested = { requestCount += 1 }

        controller.requestBrowseFolderFromEmptyStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testErrorStateOnlyAppearsForAnErrorWithoutAnImage() {
        XCTAssertTrue(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: false,
            hasError: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: true,
            hasError: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayErrorState(
            hasCurrentImage: false,
            hasError: false
        ))
    }

    func testErrorStateOpenRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onOpenRequested = { requestCount += 1 }

        controller.requestOpenFromErrorStateForTesting()

        XCTAssertEqual(requestCount, 1)
    }

    func testCancelledRetryResetsFailedWindowForReuse() async {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))
        for _ in 0..<100 where !controller.isShowingRecoverableErrorForTesting {
            await Task.yield()
        }
        XCTAssertTrue(controller.isShowingRecoverableErrorForTesting)

        controller.returnToEmptyStateAfterCancelledOpen()

        XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
        XCTAssertFalse(controller.isErrorStateVisibleForTesting)
        XCTAssertFalse(controller.hasAssignedOpenRequest)
    }

    func testErrorStateGetsVisibleLayoutAfterFailedOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let invalidPNG = root.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalidPNG)

        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.showWindow(nil)
        controller.open(url: invalidPNG)
        for _ in 0..<100 where !controller.isShowingRecoverableErrorForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }

        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(controller.errorRetryButtonForTesting)
        var ancestor: NSView? = button
        while let current = ancestor, !(current is ErrorStateView) {
            ancestor = current.superview
        }
        let errorStateView = try XCTUnwrap(ancestor)

        XCTAssertGreaterThan(errorStateView.frame.width, 0)
        XCTAssertGreaterThan(errorStateView.frame.height, 0)
        var visibilityChain: [String] = []
        var visibilityAncestor: NSView? = errorStateView
        while let current = visibilityAncestor {
            visibilityChain.append("\(type(of: current)): hidden=\(current.isHidden) frame=\(current.frame)")
            visibilityAncestor = current.superview
        }
        XCTAssertFalse(
            errorStateView.isHiddenOrHasHiddenAncestor,
            visibilityChain.joined(separator: " | ")
        )
    }

    func testErrorStateButtonHasNoGestureRecognizerInAncestorChain() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let button = try XCTUnwrap(controller.errorRetryButtonForTesting)
        var ancestor = button.superview
        while let view = ancestor {
            XCTAssertTrue(view.gestureRecognizers.isEmpty)
            ancestor = view.superview
        }
    }

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
            XCTAssertTrue(
                view.gestureRecognizers.isEmpty,
                "Interactive empty-state controls must not sit below a gesture-recognizing canvas"
            )
            ancestor = view.superview
        }
    }

    func testFilmstripMenuValidationReflectsSettingState() {
        let defaults = UserDefaults(suiteName: "ImageViewAppTests.Filmstrip.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let controller = MainWindowController(window: nil, settings: settings)
        let item = NSMenuItem(title: "Show Filmstrip", action: #selector(MainWindowController.toggleFilmstrip(_:)), keyEquivalent: "")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        settings.showsFilmstrip = true
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
    }

    func testFilmstripRequiresEnabledLoadedFitScaleAndPointerActivity() {
        XCTAssertTrue(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            canvasScale: 1.01,
            pointerIsActive: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: false,
            canvasScale: 1,
            pointerIsActive: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            canvasScale: 1.011,
            pointerIsActive: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: false,
            hasLoadedImage: true,
            canvasScale: 1,
            pointerIsActive: true
        ))
        XCTAssertFalse(MainWindowController.shouldDisplayFilmstripOverlay(
            isEnabled: true,
            hasLoadedImage: true,
            canvasScale: 1,
            pointerIsActive: false
        ))
    }

    func testFilmstripDoesNotScheduleAutoHideWhilePointerIsOverOverlay() {
        XCTAssertFalse(MainWindowController.shouldAutoHideFilmstrip(isEnabled: true, pointerIsOverOverlay: true))
        XCTAssertTrue(MainWindowController.shouldAutoHideFilmstrip(isEnabled: true, pointerIsOverOverlay: false))
        XCTAssertFalse(MainWindowController.shouldAutoHideFilmstrip(isEnabled: false, pointerIsOverOverlay: false))
    }

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

        XCTAssertEqual(
            MainWindowController.pageControlAvailability(navigationState: firstState),
            .init(previous: false, next: true)
        )
        XCTAssertEqual(
            MainWindowController.pageControlAvailability(navigationState: secondState),
            .init(previous: true, next: false)
        )
    }

    func testPageControlsStayVisibleWhileHovered() {
        XCTAssertFalse(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: true))
        XCTAssertTrue(MainWindowController.shouldAutoHidePageControls(pointerIsOverControls: false))
    }

    func testFilmstripAndPageControlsShareDisappearanceTiming() {
        XCTAssertEqual(MainWindowController.overlayAutoHideDelay, 1.8)
        XCTAssertEqual(MainWindowController.overlayFadeOutDuration, 0.18)
    }

    func testInspectorMenuValidationReflectsSettingState() {
        let defaults = UserDefaults(suiteName: "ImageViewAppTests.Inspector.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let controller = MainWindowController(window: nil, settings: settings)
        let item = NSMenuItem(title: "Show Info", action: #selector(MainWindowController.toggleInspector(_:)), keyEquivalent: "")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        settings.showsInspector = true
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
    }

    func testOpeningFolderShowsBrowserAndHidesImageOnlyStatus() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        controller.openFolderForTesting(folder, items: [item])

        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertFalse(controller.isCanvasVisibleForTesting)
        XCTAssertTrue(controller.isImageStatusContentHiddenForTesting)
        XCTAssertFalse(controller.isInspectorVisibleForTesting)
        XCTAssertFalse(controller.isFilmstripVisibleForTesting)
        XCTAssertFalse(controller.isPageControlsVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 1)
    }

    func testOpeningImageAfterFolderModeReturnsToViewerMode() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.openFolderForTesting(folder, items: [])

        controller.open(url: folder.appendingPathComponent("one.png"))

        XCTAssertFalse(controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testBrowserOpenItemCallbackCallsOpenURLAndHidesFolderBrowser() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.openFolderForTesting(folder, items: [item])

        controller.openFirstFolderBrowserItemForTesting()

        XCTAssertTrue(controller.hasAssignedOpenRequest)
        XCTAssertFalse(controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(controller.isCanvasVisibleForTesting)
    }

    func testFolderBrowserTrashCallbackUsesConfirmationAndKeepsFolderBrowserVisible() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let movedToTrash = MainWindowLockedValue<[URL]>([])
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToTrash: { urls in
                movedToTrash.set(urls)
                return BatchOperationResult(succeeded: urls)
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            confirmTrash: { count in
                XCTAssertEqual(count, 1)
                return true
            }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where controller.folderBrowserItemCountForTesting != 0 {
            await Task.yield()
        }

        XCTAssertEqual(movedToTrash.value, [item.url])
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertFalse(controller.isCanvasVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 0)
    }

    func testFolderBrowserMoveCallbackUsesDirectoryPickerSkipPolicyAndStaysInFolderMode() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let destination = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let moved = MainWindowLockedValue<(urls: [URL], destination: URL, policy: MoveConflictPolicy)?>(nil)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToFolder: { urls, destinationFolder, policy in
                moved.set((urls, destinationFolder, policy))
                return BatchOperationResult(succeeded: urls)
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            chooseDestinationFolder: { destination }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserMoveForTesting()
        for _ in 0..<100 where moved.value == nil {
            await Task.yield()
        }

        XCTAssertEqual(moved.value?.urls, [item.url])
        XCTAssertEqual(moved.value?.destination, destination)
        XCTAssertEqual(moved.value?.policy, .skip)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testFolderBrowserRenameCallbackUsesRenameSheetParametersAndStaysInFolderMode() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let renamedURL = folder.appendingPathComponent("Batch 05.png")
        let receivedParameters = MainWindowLockedValue<BatchRenameSheetController.RenameParameters?>(nil)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            planBatchRename: { urls, baseName, startNumber, padding in
                receivedParameters.set(.init(baseName: baseName, startNumber: startNumber, padding: padding))
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: renamedURL)],
                    failures: []
                )
            },
            executeRenamePlan: { _ in BatchOperationResult(succeeded: [item.url]) }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { items, confirm in
                XCTAssertEqual(items, [item])
                confirm(.init(baseName: "Batch", startNumber: 5, padding: 2))
            }
        )
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where receivedParameters.value == nil {
            await Task.yield()
        }

        XCTAssertEqual(receivedParameters.value, .init(baseName: "Batch", startNumber: 5, padding: 2))
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertEqual(controller.folderBrowserItemCountForTesting, 1)
    }

    func testFolderBrowserBatchActionsReturnWhenSelectionIsEmpty() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let operationCount = MainWindowLockedValue(0)
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [] },
            moveToTrash: { _ in
                operationCount.update { $0 += 1 }
                return BatchOperationResult()
            },
            moveToFolder: { _, _, _ in
                operationCount.update { $0 += 1 }
                return BatchOperationResult()
            },
            planBatchRename: { _, _, _, _ in
                operationCount.update { $0 += 1 }
                return BatchRenamePlan(proposals: [], failures: [])
            }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(
            confirmTrash: { _ in
                operationCount.update { $0 += 1 }
                return true
            },
            chooseDestinationFolder: {
                operationCount.update { $0 += 1 }
                return folder
            },
            requestRenameParameters: { _, _ in operationCount.update { $0 += 1 } }
        )
        await controller.openFolderForTesting(folder, scannerItems: [])

        controller.triggerFolderBrowserTrashForTesting()
        controller.triggerFolderBrowserMoveForTesting()
        controller.triggerFolderBrowserRenameForTesting()

        XCTAssertEqual(operationCount.value, 0)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testFolderBrowserOperationStatusIsRenderedAfterFailure() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = ImageItem(url: folder.appendingPathComponent("one.png"), format: .png)
        let failure = BatchFileFailure(url: item.url, reason: .trashFailed("locked"))
        let folderViewModel = FolderBrowserViewModel(
            scanFolder: { _ in [item] },
            moveToTrash: { _ in BatchOperationResult(failures: [failure]) }
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: folderViewModel
        )
        controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        await controller.openFolderForTesting(folder, scannerItems: [item])
        controller.selectFolderBrowserItemsForTesting([item.id])

        controller.triggerFolderBrowserTrashForTesting()
        let expectedStatus = "\(String(format: AppStrings.text("folderBrowser.operation.failed"), 1)) · " +
            "\(String(format: AppStrings.text("folderBrowser.status.failure.one"), 1)) · " +
            "one.png: \(String(format: AppStrings.text("folderBrowser.failure.trashFailed"), "locked"))"
        for _ in 0..<100 where controller.folderBrowserOperationStatusTextForTesting != expectedStatus {
            await Task.yield()
        }

        XCTAssertEqual(controller.folderBrowserOperationStatusTextForTesting, expectedStatus)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testTitleBarGridButtonOpensCurrentImageFolderWithoutChangingWindowTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("one.png")
        try writeTestPNG(to: imageURL)
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        controller.open(url: imageURL)
        for _ in 0..<100 where controller.window?.title == "ImageView" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let title = controller.window?.title

        controller.performTitleBarBrowseCurrentFolderForTesting(items: [
            ImageItem(url: imageURL, format: .png)
        ])

        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
        XCTAssertEqual(controller.window?.title, title)
    }

    func testGridButtonTogglesBackToLiveViewerWithoutRescanning() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.items[0]])
        fixture.controller.openFirstFolderBrowserItemForTesting()

        fixture.controller.performTitleBarGridToggleForTesting()
        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)

        fixture.controller.performTitleBarGridToggleForTesting()
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
        XCTAssertEqual(fixture.scanCount.value, 1)
    }

    func testOpeningGridItemEnablesBackAndBackForwardReuseLiveViews() async throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: [fixture.items[0]])
        fixture.controller.openFirstFolderBrowserItemForTesting()

        XCTAssertTrue(fixture.controller.canGoBackForTesting)
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        fixture.controller.goForwardForTesting()
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
        XCTAssertEqual(fixture.scanCount.value, 1)
    }

    func testDirectImageOpenDoesNotInventBackHistory() throws {
        let fixture = try makeFolderNavigationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }

        fixture.controller.open(url: fixture.items[0].url)

        XCTAssertFalse(fixture.controller.canGoBackForTesting)
        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
    }

    func testOpeningNewGridItemReplacesForwardRouteAndRecordsLastOpenedItem() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["one.png", "two.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)

        fixture.controller.openFolderBrowserItemForTesting(at: 1)

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, fixture.items[1].id)
    }

    func testCancellingUnsavedGridItemOpenPreservesRouteHistoryAndLastOpenedItem() async throws {
        let fixture = try makeFolderNavigationFixture(itemNames: ["one.png", "two.png"])
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        fixture.controller.rotateClockwise(nil)
        XCTAssertTrue(fixture.controller.hasUnsavedEditsForTesting)
        fixture.controller.goBackForTesting()
        fixture.controller.setUnsavedChangesChoiceForTesting(.cancel)

        fixture.controller.openFolderBrowserItemForTesting(at: 1)

        XCTAssertTrue(fixture.controller.isFolderBrowserVisibleForTesting)
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, fixture.items[0].url.standardizedFileURL)
        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, fixture.items[0].id)
    }

    func testDeletingForwardViewerTargetAfterBackDisablesForward() async throws {
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["one.png", "two.png"],
            moveToTrash: { BatchOperationResult(succeeded: $0) }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        fixture.controller.goBackForTesting()
        XCTAssertTrue(fixture.controller.canGoForwardForTesting)
        fixture.controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[0].id])

        fixture.controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where fixture.controller.folderBrowserItemCountForTesting != 1 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertNil(fixture.controller.forwardViewerURLForTesting)
        XCTAssertNil(fixture.controller.lastOpenedFolderItemIDForTesting)
    }

    func testRenamingForwardViewerTargetAfterBackMigratesRouteAndViewerNavigation() async throws {
        let renamedURLBox = MainWindowLockedValue<URL?>(nil)
        let fixture = try makeFolderNavigationFixture(
            moveToTrash: nil,
            planBatchRename: { urls, _, _, _ in
                let destination = urls[0].deletingLastPathComponent().appendingPathComponent("renamed.png")
                renamedURLBox.set(destination)
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: destination)],
                    failures: []
                )
            },
            executeRenamePlan: { plan in
                BatchOperationResult(succeeded: plan.proposals.map(\.source))
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        fixture.controller.goBackForTesting()
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[0].id])
        fixture.controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { _, confirm in
                confirm(.init(baseName: "renamed", startNumber: 1, padding: 2))
            }
        )

        fixture.controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where fixture.controller.lastOpenedFolderItemIDForTesting == fixture.items[0].id {
            await Task.yield()
        }
        let renamedURL = try XCTUnwrap(renamedURLBox.value).standardizedFileURL

        XCTAssertEqual(fixture.controller.lastOpenedFolderItemIDForTesting, renamedURL)
        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, renamedURL)
        XCTAssertEqual(fixture.controller.viewerNavigationURLForTesting, renamedURL)
        fixture.controller.goForwardForTesting()
        XCTAssertEqual(fixture.controller.currentViewerRouteURLForTesting, renamedURL)
        XCTAssertTrue(fixture.controller.isCanvasVisibleForTesting)
    }

    func testDeletingNavigatedForwardTargetAfterBackClearsForwardAndViewerNavigation() async throws {
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["a.png", "b.png"],
            moveToTrash: { BatchOperationResult(succeeded: $0) }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }
        fixture.controller.goBackForTesting()
        fixture.controller.batchActionDialogProviderForTesting = .init(confirmTrash: { _ in true })
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[1].id])

        fixture.controller.triggerFolderBrowserTrashForTesting()
        for _ in 0..<100 where fixture.controller.folderBrowserItemCountForTesting != 1 {
            await Task.yield()
        }

        XCTAssertFalse(fixture.controller.canGoForwardForTesting)
        XCTAssertNil(fixture.controller.forwardViewerURLForTesting)
        XCTAssertEqual(fixture.controller.viewerNavigationURLsForTesting, [fixture.items[0].url.standardizedFileURL])
    }

    func testRenamingNavigatedForwardTargetAfterBackMigratesForwardAndAllViewerItems() async throws {
        let renamedURLBox = MainWindowLockedValue<URL?>(nil)
        let fixture = try makeFolderNavigationFixture(
            itemNames: ["a.png", "b.png"],
            planBatchRename: { urls, _, _, _ in
                let destination = urls[0].deletingLastPathComponent().appendingPathComponent("renamed-b.png")
                renamedURLBox.set(destination)
                return BatchRenamePlan(
                    proposals: [RenameProposal(source: urls[0], destination: destination)],
                    failures: []
                )
            },
            executeRenamePlan: { plan in
                BatchOperationResult(succeeded: plan.proposals.map(\.source))
            }
        )
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await fixture.controller.openFolderForTesting(fixture.folder, scannerItems: fixture.items)
        fixture.controller.openFirstFolderBrowserItemForTesting()
        for _ in 0..<100 where !fixture.controller.canEditCurrentImageForTesting {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<100 where fixture.controller.viewerNavigationURLsForTesting.count != 2 {
            await Task.yield()
        }
        fixture.controller.showNextImage(nil)
        for _ in 0..<100 where fixture.controller.viewerNavigationURLForTesting != fixture.items[1].url {
            await Task.yield()
        }
        fixture.controller.goBackForTesting()
        fixture.controller.selectFolderBrowserItemsForTesting([fixture.items[1].id])
        fixture.controller.batchActionDialogProviderForTesting = .init(
            requestRenameParameters: { _, confirm in
                confirm(.init(baseName: "renamed-b", startNumber: 1, padding: 2))
            }
        )

        fixture.controller.triggerFolderBrowserRenameForTesting()
        for _ in 0..<100 where renamedURLBox.value == nil {
            await Task.yield()
        }
        let renamedURL = try XCTUnwrap(renamedURLBox.value).standardizedFileURL
        for _ in 0..<100 where fixture.controller.forwardViewerURLForTesting != renamedURL {
            await Task.yield()
        }

        XCTAssertEqual(fixture.controller.forwardViewerURLForTesting, renamedURL)
        XCTAssertEqual(
            Set(fixture.controller.viewerNavigationURLsForTesting),
            Set([fixture.items[0].url.standardizedFileURL, renamedURL])
        )
        XCTAssertFalse(fixture.controller.viewerNavigationURLsForTesting.contains(fixture.items[1].url.standardizedFileURL))
    }

    func testTitleBarGridButtonTooltipIsLocalized() {
        XCTAssertEqual(
            MainWindowController.titleBarBrowseFolderToolTip(preferredLanguages: ["en"]),
            "Browse Current Folder"
        )
        XCTAssertEqual(
            MainWindowController.titleBarBrowseFolderToolTip(preferredLanguages: ["zh-Hans"]),
            "浏览当前文件夹"
        )
    }

    private func writeTestPNG(to url: URL) throws {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        try XCTUnwrap(representation?.representation(using: .png, properties: [:])).write(to: url)
    }

    private func makeFolderNavigationFixture(
        itemNames: [String] = ["one.png"],
        moveToTrash: FolderBrowserViewModel.MoveToTrash? = nil,
        planBatchRename: FolderBrowserViewModel.PlanBatchRename? = nil,
        executeRenamePlan: FolderBrowserViewModel.ExecuteRenamePlan? = nil
    ) throws -> (
        folder: URL,
        items: [ImageItem],
        scanCount: MainWindowLockedValue<Int>,
        controller: MainWindowController
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let items = try itemNames.map { name -> ImageItem in
            let imageURL = folder.appendingPathComponent(name)
            try writeTestPNG(to: imageURL)
            return ImageItem(url: imageURL, format: .png)
        }
        let scanCount = MainWindowLockedValue(0)
        let viewModel = FolderBrowserViewModel(
            scanFolder: { _ in
                scanCount.update { $0 += 1 }
                return items
            },
            moveToTrash: moveToTrash,
            planBatchRename: planBatchRename,
            executeRenamePlan: executeRenamePlan
        )
        let controller = MainWindowController(
            settings: AppSettings(defaults: makeIsolatedDefaults()),
            folderBrowserViewModel: viewModel
        )
        return (folder, items, scanCount, controller)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.MainWindowController.\(UUID().uuidString)")!
    }
}

private final class MainWindowLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func update(_ update: (inout Value) -> Void) {
        lock.lock()
        update(&storedValue)
        lock.unlock()
    }
}
