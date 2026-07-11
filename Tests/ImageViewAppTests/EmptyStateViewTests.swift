import XCTest
@testable import ImageViewApp

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
