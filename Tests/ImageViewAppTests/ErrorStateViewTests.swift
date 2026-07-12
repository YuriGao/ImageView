import XCTest
@testable import ImageViewApp

@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testDisplaysErrorAndLocalizedRetryButton() {
        let chinese = ErrorStateView(preferredLanguages: ["zh-Hans"])
        chinese.message = "不支持的图片格式：txt"
        XCTAssertEqual(chinese.messageForTesting, "不支持的图片格式：txt")
        XCTAssertEqual(chinese.buttonTitleForTesting, "重新选择图片…")

        let english = ErrorStateView(preferredLanguages: ["en"])
        XCTAssertEqual(english.buttonTitleForTesting, "Choose Another Image…")
    }

    func testRetryButtonInvokesCallbackOnce() {
        let view = ErrorStateView(preferredLanguages: ["en"])
        var count = 0
        view.onRetryRequested = { count += 1 }

        view.performRetryForTesting()

        XCTAssertEqual(count, 1)
    }
}
