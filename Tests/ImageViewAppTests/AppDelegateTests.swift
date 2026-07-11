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

    func testAppearanceMenuContainsThreeLocalizedMutuallyExclusiveChoices() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        let delegate = AppDelegate(settings: settings)
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
        let appearanceMenu = menu.items[2].submenu?
            .item(withTitle: "Appearance")?.submenu

        XCTAssertEqual(appearanceMenu?.items.map(\.title), ["System", "Light", "Dark"])
        XCTAssertEqual(appearanceMenu?.items.map(\.state), [.on, .off, .off])
        XCTAssertTrue(appearanceMenu?.items.allSatisfy { $0.target === delegate } == true)
        XCTAssertTrue(appearanceMenu?.items.allSatisfy { $0.keyEquivalent.isEmpty } == true)
    }

    func testAppearanceMenuLocalizesForSimplifiedChinese() {
        let delegate = AppDelegate(settings: AppSettings(defaults: makeIsolatedDefaults()))
        let menu = delegate.makeMainMenu(preferredLanguages: ["zh-Hans"])
        let appearanceMenu = menu.items[2].submenu?
            .item(withTitle: "外观")?.submenu

        XCTAssertEqual(appearanceMenu?.items.map(\.title), ["跟随系统", "浅色", "深色"])
    }

    func testAppearanceNameMapsSettingsToAppKitAppearances() {
        XCTAssertNil(AppDelegate.appearanceName(for: .system))
        XCTAssertEqual(AppDelegate.appearanceName(for: .light), .aqua)
        XCTAssertEqual(AppDelegate.appearanceName(for: .dark), .darkAqua)
    }

    func testAppearanceMenuSelectionPersistsAndUpdatesCheckmarks() throws {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        let delegate = AppDelegate(settings: settings)
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
        let appearanceMenu = menu.items[2].submenu?
            .item(withTitle: "Appearance")?.submenu

        let darkItem = try XCTUnwrap(appearanceMenu?.item(withTitle: "Dark"))
        let action = try XCTUnwrap(darkItem.action)
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: darkItem.target, from: darkItem))

        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(appearanceMenu?.items.map(\.state), [.off, .off, .on])
        NSApplication.shared.appearance = nil
    }

    func testAppTerminatesAfterLastWindowCloses() {
        let delegate = AppDelegate()

        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ImageViewAppTests.AppDelegate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
