import XCTest
@testable import ImageViewApp

final class AppStringsTests: XCTestCase {
    func testChinesePreferredLanguageUsesSimplifiedChinese() {
        XCTAssertEqual(AppStrings.text("menu.file", preferredLanguages: ["zh-Hans"]), "文件")
    }

    func testUnsupportedPreferredLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppStrings.text("menu.file", preferredLanguages: ["fr"]), "File")
    }

    func testEveryMenuLabelHasChineseAndEnglishTranslations() {
        let menuKeys = [
            "menu.file", "menu.view", "menu.image", "menu.window", "menu.help",
            "menu.app.settings", "menu.app.quit",
            "menu.file.open", "menu.file.openRecent", "menu.file.rename", "menu.file.reveal", "menu.file.copyPath", "menu.file.moveToTrash", "menu.file.close", "menu.file.noRecentImages",
            "menu.view.previousImage", "menu.view.nextImage", "menu.view.actualSize", "menu.view.zoomToFit", "menu.view.showFilmstrip", "menu.view.showInfo", "menu.view.appearance", "menu.view.appearance.system", "menu.view.appearance.light", "menu.view.appearance.dark", "menu.view.enterFullScreen",
            "menu.image.rotateClockwise", "menu.image.rotateCounterclockwise", "menu.image.flipHorizontal", "menu.image.flipVertical", "menu.image.crop", "menu.image.saveEdits", "menu.image.saveAs", "menu.image.discardEdits",
            "menu.window.minimize", "menu.window.zoom", "menu.window.bringAllToFront",
            "menu.help.imageView"
        ]

        for key in menuKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }
}
