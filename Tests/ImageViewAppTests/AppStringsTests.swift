import XCTest
@testable import ImageViewApp

final class AppStringsTests: XCTestCase {
    func testFileAssociationSettingsLocalizeInEnglishAndSimplifiedChinese() {
        XCTAssertEqual(AppStrings.text("settings.fileAssociations.title", preferredLanguages: ["en"]), "File Associations")
        XCTAssertEqual(AppStrings.text("settings.fileAssociations.apply", preferredLanguages: ["en"]), "Set ImageView as Default")
        XCTAssertEqual(AppStrings.text("settings.fileAssociations.title", preferredLanguages: ["zh-Hans"]), "文件关联")
        XCTAssertEqual(AppStrings.text("settings.fileAssociations.apply", preferredLanguages: ["zh-Hans"]), "将 ImageView 设为默认")
    }

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
            "menu.file.open", "menu.file.browseFolder", "menu.file.openRecent", "menu.file.rename", "menu.file.reveal", "menu.file.copyPath", "menu.file.moveToTrash", "menu.file.close", "menu.file.noRecentImages",
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

    func testEverySettingsLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.settingsKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryEmptyStateLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.emptyStateKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryErrorStateLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.errorStateKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryTitleBarLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.titleBarKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryFolderBrowserWorkflowLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.folderBrowserKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryInspectorLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.inspectorKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testEveryInteractionLabelHasChineseAndEnglishTranslations() {
        for key in AppStrings.interactionKeys {
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["en"]), key)
            XCTAssertNotEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), key)
        }
    }

    func testSafetyPromptsLocalizeInSimplifiedChinese() {
        XCTAssertEqual(AppStrings.text("viewer.confirmTrash.title", preferredLanguages: ["zh-Hans"]), "移到废纸篓？")
        XCTAssertEqual(AppStrings.text("unsavedChanges.button.save", preferredLanguages: ["zh-Hans"]), "保存")
        XCTAssertEqual(AppStrings.text("crop.button.apply", preferredLanguages: ["zh-Hans"]), "应用")
    }

    func testInspectorLabelsLocalizeInSimplifiedChinese() {
        XCTAssertEqual(AppStrings.text("inspector.title", preferredLanguages: ["zh-Hans"]), "信息")
        XCTAssertEqual(AppStrings.text("inspector.format", preferredLanguages: ["zh-Hans"]), "格式")
        XCTAssertEqual(AppStrings.text("inspector.modified", preferredLanguages: ["zh-Hans"]), "修改时间")
    }

    func testFolderBrowserWorkflowLabelsLocalizeInEnglishAndSimplifiedChinese() {
        XCTAssertEqual(AppStrings.text("folderBrowser.searchPlaceholder", preferredLanguages: ["en"]), "Search images")
        XCTAssertEqual(AppStrings.text("folderBrowser.searchPlaceholder", preferredLanguages: ["zh-Hans"]), "搜索图片")
        XCTAssertEqual(AppStrings.text("batchRename.title", preferredLanguages: ["en"]), "Batch Rename")
        XCTAssertEqual(AppStrings.text("batchRename.title", preferredLanguages: ["zh-Hans"]), "批量重命名")
    }

    func testFolderBrowserNavigationAndRecoveryLabelsHaveExactEnglishAndSimplifiedChineseCopy() {
        let expected: [(String, String, String)] = [
            ("titleBar.back", "Back", "返回"),
            ("titleBar.forward", "Forward", "前进"),
            ("titleBar.showFolder", "Show Folder", "显示文件夹"),
            ("titleBar.showImage", "Show Image", "显示图片"),
            ("folderBrowser.state.loading.title", "Loading…", "正在加载…"),
            ("folderBrowser.state.emptyFolder.title", "Empty Folder", "文件夹为空"),
            ("folderBrowser.state.filteredEmpty.title", "No Filter Results", "没有符合筛选条件的结果"),
            ("folderBrowser.state.loadFailed.title", "Load Failed", "加载失败"),
            ("folderBrowser.button.retry", "Retry", "重试"),
            ("folderBrowser.button.clearFilters", "Clear Filters", "清除筛选"),
            ("folderBrowser.button.chooseAnotherFolder", "Choose Another Folder…", "选择其他文件夹…")
        ]

        for (key, english, chinese) in expected {
            XCTAssertEqual(AppStrings.text(key, preferredLanguages: ["en"]), english, key)
            XCTAssertEqual(AppStrings.text(key, preferredLanguages: ["zh-Hans"]), chinese, key)
        }
    }

    func testStaleRecoveryAlertLabelsHaveEnglishAndSimplifiedChineseCopy() {
        XCTAssertEqual(
            AppStrings.text("folderBrowser.recovery.alert.title", preferredLanguages: ["en"]),
            "File Recovery Required"
        )
        XCTAssertEqual(
            AppStrings.text("folderBrowser.recovery.alert.title", preferredLanguages: ["zh-Hans"]),
            "需要恢复文件"
        )
        XCTAssertEqual(
            AppStrings.text("folderBrowser.recovery.alert.folder", preferredLanguages: ["en"]),
            "A batch rename in this folder requires manual recovery: %@"
        )
        XCTAssertEqual(
            AppStrings.text("folderBrowser.recovery.alert.folder", preferredLanguages: ["zh-Hans"]),
            "此文件夹中的批量重命名需要手动恢复：%@"
        )
    }
}
