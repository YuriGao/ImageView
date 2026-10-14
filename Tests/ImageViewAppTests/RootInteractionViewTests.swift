import AppKit
import XCTest
@testable import ImageViewApp

/// 回归：窗口开启了 `acceptsMouseMovedEvents`，整块屏幕上的鼠标移动都会经响应链
/// 送进 `RootInteractionView.mouseMoved(with:)`。如果不判断位置，鼠标在窗口外移动
/// 也会唤出翻页箭头和胶片条。
@MainActor
final class RootInteractionViewTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ImageViewAppTests.RootInteractionView.\(UUID().uuidString)")!
    }

    private func mouseMovedEvent(windowNumber: Int, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
    }

    func testPointerMovesAreOnlyReportedInsideTheView() throws {
        let controller = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))
        addTeardownBlock { @MainActor in controller.close() }
        let window = try XCTUnwrap(controller.window)
        let rootView = try XCTUnwrap(window.contentView as? RootInteractionView)
        var reportedMoves = 0
        rootView.onPointerMoved = { reportedMoves += 1 }

        rootView.mouseMoved(
            with: mouseMovedEvent(windowNumber: window.windowNumber, at: NSPoint(x: 120, y: 160))
        )
        XCTAssertEqual(reportedMoves, 1, "窗口内的移动应上报，用于唤出浮层")

        for outsidePoint in [NSPoint(x: -400, y: -400), NSPoint(x: 4000, y: 4000)] {
            rootView.mouseMoved(
                with: mouseMovedEvent(windowNumber: window.windowNumber, at: outsidePoint)
            )
        }
        XCTAssertEqual(reportedMoves, 1, "窗口外的移动不应唤出翻页箭头和胶片条")
    }
}
