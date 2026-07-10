import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class MainWindowControllerTests: XCTestCase {
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

    func testHUDVisibilityPolicyKeepsPinnedHUDVisibleAndTimesUnpinnedActivity() {
        XCTAssertEqual(
            MainWindowController.hudVisibilityAction(isPinned: true, isActivity: true),
            .showIndefinitely
        )
        XCTAssertFalse(MainWindowController.shouldScheduleHUDHide(isPinned: true))

        XCTAssertEqual(
            MainWindowController.hudVisibilityAction(isPinned: false, isActivity: true),
            .showTemporarily
        )
        XCTAssertTrue(MainWindowController.shouldScheduleHUDHide(isPinned: false))

        XCTAssertEqual(
            MainWindowController.hudVisibilityAction(isPinned: false, isActivity: false),
            .hide
        )
    }

    func testToolsToolbarVisibilityRequiresHUDAndInactiveCropMode() {
        XCTAssertTrue(MainWindowController.shouldShowToolsToolbar(isHUDVisible: true, isCropping: false))
        XCTAssertFalse(MainWindowController.shouldShowToolsToolbar(isHUDVisible: false, isCropping: false))
        XCTAssertFalse(MainWindowController.shouldShowToolsToolbar(isHUDVisible: true, isCropping: true))
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

    func testMenuCommandAvailabilityRequiresImageAndUnsavedStateWhereAppropriate() {
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .startCropping,
                hasCurrentItem: true,
                hasCurrentImage: true,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.rotateClockwise),
                hasCurrentItem: true,
                hasCurrentImage: false,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .editOperation(.mirrorHorizontal),
                hasCurrentItem: false,
                hasCurrentImage: true,
                hasUnsavedEdits: false
            )
        )
        XCTAssertFalse(
            MainWindowController.isMenuCommandEnabled(
                .saveEdits,
                hasCurrentItem: true,
                hasCurrentImage: true,
                hasUnsavedEdits: false
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .discardEdits,
                hasCurrentItem: true,
                hasCurrentImage: true,
                hasUnsavedEdits: true
            )
        )
        XCTAssertTrue(
            MainWindowController.isMenuCommandEnabled(
                .saveEditsAs,
                hasCurrentItem: true,
                hasCurrentImage: true,
                hasUnsavedEdits: true
            )
        )
    }

    func testFullscreenBackgroundSettingOnlyChangesFullscreenCanvasColor() {
        XCTAssertEqual(
            MainWindowController.canvasBackgroundColor(isFullScreen: true, usesBlackFullscreenBackground: true),
            .black
        )
        XCTAssertEqual(
            MainWindowController.canvasBackgroundColor(isFullScreen: true, usesBlackFullscreenBackground: false),
            .windowBackgroundColor
        )
        XCTAssertEqual(
            MainWindowController.canvasBackgroundColor(isFullScreen: false, usesBlackFullscreenBackground: false),
            .windowBackgroundColor
        )
        XCTAssertEqual(
            MainWindowController.canvasBackgroundColor(isFullScreen: false, usesBlackFullscreenBackground: true),
            .windowBackgroundColor
        )
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
}
