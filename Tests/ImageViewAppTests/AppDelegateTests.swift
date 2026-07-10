import XCTest
import AppKit
@testable import ImageViewApp

@MainActor
final class AppDelegateTests: XCTestCase {
    func testHelpSearchUsesAnOffscreenMenuInsteadOfTheVisibleHelpMenu() {
        let delegate = AppDelegate()
        let visibleHelpMenu = delegate.makeMainMenu(preferredLanguages: ["en"]).items[5].submenu

        delegate.configureHelpMenuSearchSuppression()

        XCTAssertFalse(NSApp.helpMenu === visibleHelpMenu)
        XCTAssertTrue(NSApp.helpMenu?.items.isEmpty == true)
    }

    func testMainMenuContainsCompleteLocalizedMenuHierarchy() {
        let delegate = AppDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])

        XCTAssertEqual(menu.items.compactMap(\.submenu?.title), [
            "ImageView",
            AppStrings.text("menu.file", preferredLanguages: ["en"]),
            AppStrings.text("menu.view", preferredLanguages: ["en"]),
            AppStrings.text("menu.image", preferredLanguages: ["en"]),
            AppStrings.text("menu.window", preferredLanguages: ["en"]),
            AppStrings.text("menu.help", preferredLanguages: ["en"])
        ])
        XCTAssertNotNil(menu.items[2].submenu?.item(withTitle: "Next Image"))
        XCTAssertNotNil(menu.items[3].submenu?.item(withTitle: "Rotate Clockwise"))
        XCTAssertNotNil(menu.items[3].submenu?.item(withTitle: "Crop"))
    }

    func testMainMenuLocalizesSubmenuItemsForSimplifiedChinese() {
        let delegate = AppDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["zh-Hans"])

        XCTAssertNotNil(menu.items[1].submenu?.item(withTitle: "打开…"))
        XCTAssertNotNil(menu.items[2].submenu?.item(withTitle: "显示胶片预览"))
        XCTAssertNotNil(menu.items[3].submenu?.item(withTitle: "顺时针旋转"))
        XCTAssertNotNil(menu.items[4].submenu?.item(withTitle: "全部置于前台"))
        XCTAssertNotNil(menu.items[5].submenu?.item(withTitle: "ImageView 帮助"))
    }

    func testAppTerminatesAfterLastWindowCloses() {
        let delegate = AppDelegate()

        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
