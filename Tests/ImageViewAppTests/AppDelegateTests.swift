import XCTest
import AppKit
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class AppDelegateTests: XCTestCase {
    func testOpenPanelAllowsOnlySupportedImageFormats() {
        let panel = NSOpenPanel()

        AppDelegate.configureOpenPanel(panel)

        let expected = Set(SupportedImageFormat.allCases.compactMap(\.contentType).map(\.identifier))
        XCTAssertEqual(Set(panel.allowedContentTypes.map(\.identifier)), expected)
        XCTAssertFalse(panel.allowsOtherFileTypes)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertTrue(panel.allowsMultipleSelection)
    }

    @MainActor
    private final class WindowHarness {
        var openRequests: [URL] = []
        var folderOpenRequests: [URL] = []
        var recentURLs: [URL] = []
        var terminationCount = 0
        var showCounts: [ObjectIdentifier: Int] = [:]
        private let chosenURLs: [URL]?
        private let chosenFolderURL: URL?

        init(chosenURLs: [URL]? = nil, chosenFolderURL: URL? = nil) {
            self.chosenURLs = chosenURLs
            self.chosenFolderURL = chosenFolderURL
        }

        func makeDelegate() -> AppDelegate {
            _ = NSApplication.shared
            return AppDelegate(
                settings: AppSettings(defaults: makeIsolatedDefaults()),
                makeImageWindowController: { MainWindowController(settings: $0) },
                showImageWindow: { [weak self] controller in
                    let identifier = ObjectIdentifier(controller)
                    self?.showCounts[identifier, default: 0] += 1
                },
                openImageURL: { [weak self] controller, url in
                    self?.openRequests.append(url)
                    controller.open(url: url)
                },
                chooseImageURLs: { [weak self] in self?.chosenURLs },
                chooseFolderURL: { [weak self] in self?.chosenFolderURL },
                openFolderURL: { [weak self] controller, url in
                    self?.folderOpenRequests.append(url)
                    controller.openFolderForTesting(url, items: [])
                },
                terminateApplication: { [weak self] in self?.terminationCount += 1 },
                noteRecentDocument: { [weak self] url in
                    guard let self else { return }
                    recentURLs.removeAll { $0 == url }
                    recentURLs.insert(url, at: 0)
                },
                recentDocumentURLs: { [weak self] in self?.recentURLs ?? [] }
            )
        }

        func showCount(for controller: MainWindowController) -> Int {
            showCounts[ObjectIdentifier(controller), default: 0]
        }

        private func makeIsolatedDefaults() -> UserDefaults {
            let suiteName = "ImageViewAppTests.WindowHarness.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            return defaults
        }
    }

    func testLaunchCreatesOneEmptyImageWindow() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()

        delegate.finishLaunchingForTesting()

        XCTAssertEqual(delegate.imageWindowCount, 1)
        XCTAssertFalse(delegate.imageWindowControllersForTesting[0].hasAssignedOpenRequest)
        XCTAssertEqual(harness.showCount(for: delegate.imageWindowControllersForTesting[0]), 1)
    }

    func testEmptyStateOpenRequestUsesExistingMultiURLPipeline() {
        let urls = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")]
        let harness = WindowHarness(chosenURLs: urls)
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()

        delegate.imageWindowControllersForTesting[0].onOpenRequested?()

        XCTAssertEqual(harness.openRequests, urls)
        XCTAssertEqual(delegate.imageWindowCount, 2)
    }

    func testCancelledEmptyStateOpenRequestDoesNothing() {
        let harness = WindowHarness(chosenURLs: nil)
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()

        delegate.imageWindowControllersForTesting[0].onOpenRequested?()

        XCTAssertTrue(harness.openRequests.isEmpty)
        XCTAssertEqual(delegate.imageWindowCount, 1)
    }

    func testEmptyStateBrowseFolderRequestUsesExistingActiveWindowAndFolderPipeline() {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let harness = WindowHarness(chosenFolderURL: folder)
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        let controller = delegate.imageWindowControllersForTesting[0]

        controller.onBrowseFolderRequested?()

        XCTAssertEqual(harness.folderOpenRequests, [folder])
        XCTAssertEqual(delegate.imageWindowCount, 1)
        XCTAssertEqual(harness.showCount(for: controller), 2)
        XCTAssertTrue(controller.isFolderBrowserVisibleForTesting)
    }

    func testCancelledChooserReturnsFailedRequestingWindowToEmptyState() async {
        let harness = WindowHarness(chosenURLs: nil)
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        let controller = delegate.imageWindowControllersForTesting[0]
        controller.open(url: URL(fileURLWithPath: "/tmp/not-an-image.txt"))
        for _ in 0..<100 where !controller.isShowingRecoverableErrorForTesting {
            await Task.yield()
        }
        XCTAssertTrue(controller.isShowingRecoverableErrorForTesting)

        controller.onOpenRequested?()

        XCTAssertTrue(controller.isEmptyStateVisibleForTesting)
        XCTAssertFalse(controller.hasAssignedOpenRequest)
        XCTAssertEqual(delegate.imageWindowCount, 1)
    }

    func testFirstURLReusesEmptyWindowAndLaterURLsCreateWindows() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        let urls = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")]

        delegate.openURLs(urls)

        XCTAssertEqual(delegate.imageWindowCount, 2)
        XCTAssertEqual(harness.openRequests, urls)
        XCTAssertTrue(delegate.imageWindowControllersForTesting[0].hasAssignedOpenRequest)
        XCTAssertFalse(delegate.imageWindowControllersForTesting[0] === delegate.imageWindowControllersForTesting[1])
        XCTAssertEqual(harness.showCount(for: delegate.imageWindowControllersForTesting[0]), 2)
        XCTAssertEqual(harness.showCount(for: delegate.imageWindowControllersForTesting[1]), 1)
    }

    func testOpeningDirectoryURLUsesFolderRouteForMemoryBenchmark() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()

        delegate.openURLs([folder])

        XCTAssertEqual(harness.folderOpenRequests, [folder])
        XCTAssertTrue(harness.openRequests.isEmpty)
        XCTAssertTrue(delegate.imageWindowControllersForTesting[0].isFolderBrowserVisibleForTesting)
    }

    func testPrelaunchURLsRetainFullOrderAndDuplicates() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let duplicate = URL(fileURLWithPath: "/duplicate.png")
        let urls = [URL(fileURLWithPath: "/first.png"), duplicate, duplicate, URL(fileURLWithPath: "/last.png")]

        delegate.application(NSApplication.shared, open: urls)
        XCTAssertEqual(delegate.pendingURLsForTesting, urls)

        delegate.finishLaunchingForTesting()

        XCTAssertEqual(harness.openRequests, urls)
        XCTAssertEqual(delegate.imageWindowCount, urls.count)
        XCTAssertTrue(delegate.pendingURLsForTesting.isEmpty)
        XCTAssertEqual(
            delegate.imageWindowControllersForTesting.map(harness.showCount(for:)),
            [2, 1, 1, 1]
        )
    }

    func testClosingOneWindowKeepsOthersAndClosingFinalWindowTerminatesOnce() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        delegate.openURLs([URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")])
        let controllers = delegate.imageWindowControllersForTesting

        delegate.imageWindowDidClose(controllers[0])
        XCTAssertEqual(delegate.imageWindowCount, 1)
        XCTAssertEqual(harness.terminationCount, 0)

        delegate.imageWindowDidClose(controllers[1])
        delegate.imageWindowDidClose(controllers[1])

        XCTAssertEqual(delegate.imageWindowCount, 0)
        XCTAssertEqual(harness.terminationCount, 1)
    }

    func testClosingUnknownControllerIsIdempotent() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        let unknown = MainWindowController(settings: AppSettings(defaults: makeIsolatedDefaults()))

        delegate.imageWindowDidClose(unknown)
        delegate.imageWindowDidClose(unknown)

        XCTAssertEqual(delegate.imageWindowCount, 1)
        XCTAssertEqual(harness.terminationCount, 0)
    }

    func testSettingsWindowDoesNotPreventFinalImageWindowTermination() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        delegate.finishLaunchingForTesting()
        delegate.showPreferencesForTesting()

        delegate.imageWindowDidClose(delegate.imageWindowControllersForTesting[0])

        XCTAssertEqual(harness.terminationCount, 1)
    }

    func testMenuTargetsFollowKeyAndMostRecentlyActiveImageWindow() throws {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(menu)
        delegate.finishLaunchingForTesting(installMenu: false)
        delegate.openURLs([URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")])
        let first = delegate.imageWindowControllersForTesting[0]
        let second = delegate.imageWindowControllersForTesting[1]

        delegate.imageWindowDidBecomeKey(first)
        XCTAssertTrue(menu.items[2].submenu?.item(withTitle: "Next Image")?.target === first)

        delegate.imageWindowDidBecomeKey(second)
        XCTAssertTrue(menu.items[2].submenu?.item(withTitle: "Next Image")?.target === second)

        delegate.connectMenuTargetsForTesting()
        XCTAssertTrue(delegate.activeImageWindowControllerForTesting === second)
    }

    func testSettingsKeyKeepsMostRecentlyActiveImageMenuTarget() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(menu)
        delegate.finishLaunchingForTesting(installMenu: false)
        delegate.openURLs([URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")])
        let second = delegate.imageWindowControllersForTesting[1]
        delegate.imageWindowDidBecomeKey(second)

        delegate.showPreferencesForTesting()
        delegate.connectMenuTargetsForTesting()

        XCTAssertTrue(menu.items[2].submenu?.item(withTitle: "Next Image")?.target === second)
    }

    func testClosingFinalControllerClearsControllerMenuTargets() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(menu)
        delegate.finishLaunchingForTesting(installMenu: false)
        let controller = delegate.imageWindowControllersForTesting[0]
        delegate.imageWindowDidBecomeKey(controller)

        delegate.imageWindowDidClose(controller)

        XCTAssertNil(menu.items[2].submenu?.item(withTitle: "Next Image")?.target)
        XCTAssertTrue(menu.items[0].submenu?.item(withTitle: "Settings…")?.target === delegate)
    }

    func testConstructingOffscreenMenuDoesNotChangeInstalledMenuRouting() {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let installedMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(installedMenu)
        let offscreenMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.finishLaunchingForTesting(installMenu: false)
        let controller = delegate.imageWindowControllersForTesting[0]

        delegate.imageWindowDidBecomeKey(controller)

        XCTAssertTrue(installedMenu.items[2].submenu?.item(withTitle: "Next Image")?.target === controller)
        XCTAssertNil(offscreenMenu.items[2].submenu?.item(withTitle: "Next Image")?.target)
    }

    func testConstructingOffscreenMenuDoesNotRedirectRecentMenuRebuild() throws {
        let harness = WindowHarness()
        let delegate = harness.makeDelegate()
        let installedMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(installedMenu)
        delegate.finishLaunchingForTesting(installMenu: false)
        let installedRecentMenu = try XCTUnwrap(
            installedMenu.items[1].submenu?.item(withTitle: "Open Recent")?.submenu
        )
        let offscreenMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        let offscreenRecentMenu = try XCTUnwrap(
            offscreenMenu.items[1].submenu?.item(withTitle: "Open Recent")?.submenu
        )
        delegate.openURLs([URL(fileURLWithPath: "/first.png"), URL(fileURLWithPath: "/second.png")])
        let openedURL = URL(fileURLWithPath: "/opened-by-second-window.png")

        delegate.imageWindowControllersForTesting[1].onSuccessfulOpen?(openedURL)

        XCTAssertEqual(harness.recentURLs, [openedURL])
        XCTAssertEqual(
            installedRecentMenu.items.first?.representedObject as? URL,
            openedURL
        )
        XCTAssertNil(offscreenRecentMenu.items.first?.representedObject)
    }

    func testConstructingOffscreenMenuDoesNotRedirectAppearanceCheckmarkUpdates() throws {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        let delegate = AppDelegate(settings: settings)
        let installedMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        delegate.setInstalledMainMenuForTesting(installedMenu)
        let installedAppearanceMenu = try XCTUnwrap(
            installedMenu.items[2].submenu?.item(withTitle: "Appearance")?.submenu
        )
        let offscreenMenu = delegate.makeMainMenu(preferredLanguages: ["en"])
        let offscreenAppearanceMenu = try XCTUnwrap(
            offscreenMenu.items[2].submenu?.item(withTitle: "Appearance")?.submenu
        )
        let darkItem = try XCTUnwrap(offscreenAppearanceMenu.item(withTitle: "Dark"))
        let action = try XCTUnwrap(darkItem.action)

        XCTAssertTrue(NSApplication.shared.sendAction(action, to: darkItem.target, from: darkItem))

        XCTAssertEqual(installedAppearanceMenu.items.map(\.state), [.off, .off, .on])
        XCTAssertEqual(offscreenAppearanceMenu.items.map(\.state), [.on, .off, .off])
        NSApplication.shared.appearance = nil
    }

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
        XCTAssertNotNil(menu.items[1].submenu?.item(withTitle: "Browse Folder…"))
        XCTAssertNotNil(menu.items[3].submenu?.item(withTitle: "Rotate Clockwise"))
        XCTAssertNotNil(menu.items[3].submenu?.item(withTitle: "Crop"))
    }

    func testMainMenuLocalizesSubmenuItemsForSimplifiedChinese() {
        let delegate = AppDelegate()
        let menu = delegate.makeMainMenu(preferredLanguages: ["zh-Hans"])

        XCTAssertNotNil(menu.items[1].submenu?.item(withTitle: "打开…"))
        XCTAssertNotNil(menu.items[1].submenu?.item(withTitle: "浏览文件夹…"))
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
