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

    func testEmptyStateOpenRequestIsForwarded() {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        var requestCount = 0
        controller.onOpenRequested = { requestCount += 1 }

        controller.requestOpenFromEmptyStateForTesting()

        XCTAssertEqual(requestCount, 1)
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

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.MainWindowController.\(UUID().uuidString)")!
    }
}
