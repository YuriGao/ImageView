import AppKit
import XCTest
@testable import ImageViewApp

@MainActor
final class PageNavigationOverlayViewTests: XCTestCase {
    func testControlsUseApprovedSymbolsAndDimensions() {
        let view = PageNavigationOverlayView()

        XCTAssertEqual(PageNavigationOverlayView.controlSize, CGSize(width: 44, height: 64))
        XCTAssertEqual(view.debugPreviousButton.image?.accessibilityDescription, AppStrings.text("menu.view.previousImage"))
        XCTAssertEqual(view.debugNextButton.image?.accessibilityDescription, AppStrings.text("menu.view.nextImage"))
    }

    func testUpdateAppliesSequenceBoundaryStates() {
        let view = PageNavigationOverlayView()

        view.update(previousEnabled: false, nextEnabled: true)

        XCTAssertFalse(view.debugPreviousButton.isEnabled)
        XCTAssertTrue(view.debugNextButton.isEnabled)
    }

    func testButtonsCallNavigationCallbacks() {
        let view = PageNavigationOverlayView()
        var previousCount = 0
        var nextCount = 0
        view.onPrevious = { previousCount += 1 }
        view.onNext = { nextCount += 1 }

        view.performDebugPrevious()
        view.performDebugNext()

        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(nextCount, 1)
    }

    func testOverlayUsesAppearanceAdaptiveBorderAndBackground() {
        XCTAssertEqual(PageNavigationOverlayView.backgroundColor, .windowBackgroundColor)
        XCTAssertEqual(PageNavigationOverlayView.borderColor, .separatorColor)
        XCTAssertEqual(PageNavigationOverlayView.borderWidth(forBackingScaleFactor: 2), 0.5)
    }

    // MARK: - 鼠标点击命中
    //
    // 回归背景：浮层贴着画布，并不在父视图原点上；而 hitTest(_:) 收到的点位于父视图坐标系。
    // 曾经把该点误当自身坐标换算，再把结果交给按钮（按钮同样期望父视图坐标），
    // 两次错位叠加导致箭头矩形内任何位置都命中不到，点击穿透到画布，鼠标点击翻页完全失效。

    /// 对照组：AppKit 传给 `hitTest(_:)` 的点位于父视图坐标系。
    func testHitTestReceivesPointsInSuperviewCoordinates() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let child = NSView(frame: NSRect(x: 100, y: 100, width: 50, height: 50))
        container.addSubview(child)

        XCTAssertTrue(container.hitTest(NSPoint(x: 125, y: 125)) === child)
        XCTAssertFalse(container.hitTest(NSPoint(x: 25, y: 25)) === child)
    }

    func testArrowButtonsReceiveClicksAcrossTheirWholeVisibleRect() throws {
        let (rootView, overlay) = try makeOverlayPinnedToRealWindow()

        for button in [overlay.debugPreviousButton, overlay.debugNextButton] {
            for x in stride(from: 1.0, to: button.bounds.width - 1, by: 6) {
                for y in stride(from: 1.0, to: button.bounds.height - 1, by: 6) {
                    let pointInSuperview = button.convert(NSPoint(x: x, y: y), to: rootView)
                    let hit = overlay.hitTest(pointInSuperview)
                    XCTAssertTrue(
                        hit === button || hit?.isDescendant(of: button) == true,
                        "箭头内(\(x), \(y)) 的点击应命中按钮，实际命中：\(String(describing: hit))"
                    )
                }
            }
        }
    }

    func testOverlayKeepsPassingClicksOutsideItsButtonsThrough() throws {
        let (rootView, overlay) = try makeOverlayPinnedToRealWindow()
        let overlayCenter = NSPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        XCTAssertNil(overlay.hitTest(overlay.convert(overlayCenter, to: rootView)))

        let button = overlay.debugPreviousButton
        let aboveButton = button.convert(
            NSPoint(x: button.bounds.midX, y: button.bounds.maxY + 20),
            to: rootView
        )
        XCTAssertNil(overlay.hitTest(aboveButton))
    }

    func testArrowButtonsTriggerNavigationCallbacksWhenClicked() throws {
        let (_, overlay) = try makeOverlayPinnedToRealWindow()
        overlay.update(previousEnabled: true, nextEnabled: true)
        var previousCount = 0
        var nextCount = 0
        overlay.onPrevious = { previousCount += 1 }
        overlay.onNext = { nextCount += 1 }

        overlay.debugNextButton.performClick(nil)
        overlay.debugPreviousButton.performClick(nil)

        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(previousCount, 1)
    }

    /// 用真实窗口与约束还原箭头布局：浮层贴着画布，底边让出状态栏，因此其 frame 原点并非 (0, 0)。
    private func makeOverlayPinnedToRealWindow() throws -> (rootView: NSView, overlay: PageNavigationOverlayView) {
        let defaults = UserDefaults(
            suiteName: "ImageViewAppTests.PageNavigationOverlayView.\(UUID().uuidString)"
        )!
        let controller = MainWindowController(settings: AppSettings(defaults: defaults))
        addTeardownBlock { @MainActor in controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.layoutIfNeeded()
        let rootView = try XCTUnwrap(window.contentView)
        let overlay = controller.pageNavigationOverlayView
        overlay.isHidden = false
        overlay.alphaValue = 1
        rootView.layoutSubtreeIfNeeded()

        XCTAssertNotEqual(overlay.frame.origin, .zero, "浮层原点应让出状态栏，否则覆盖不到本次回归场景")
        return (rootView, overlay)
    }
}
