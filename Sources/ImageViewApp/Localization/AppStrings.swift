import Foundation

enum AppStrings {
    private static let packagedResourceBundleName = "ImageView_ImageViewApp"

    static let menuKeys = [
        "menu.file", "menu.view", "menu.image", "menu.window", "menu.help",
        "menu.app.settings", "menu.app.quit",
        "menu.file.open", "menu.file.browseFolder", "menu.file.openRecent", "menu.file.rename", "menu.file.reveal", "menu.file.copyPath", "menu.file.moveToTrash", "menu.file.close", "menu.file.noRecentImages",
        "menu.view.previousImage", "menu.view.nextImage", "menu.view.actualSize", "menu.view.zoomToFit", "menu.view.zoomToFitWidth", "menu.view.showFilmstrip", "menu.view.continuousReading", "menu.view.showInfo", "menu.view.appearance", "menu.view.appearance.system", "menu.view.appearance.light", "menu.view.appearance.dark", "menu.view.enterFullScreen",
        "menu.image.rotateClockwise", "menu.image.rotateCounterclockwise", "menu.image.flipHorizontal", "menu.image.flipVertical", "menu.image.crop", "menu.image.saveEdits", "menu.image.saveAs", "menu.image.discardEdits",
        "menu.window.minimize", "menu.window.zoom", "menu.window.bringAllToFront",
        "menu.help.imageView"
    ]

    static let settingsKeys = [
        "settings.title", "settings.general.title", "settings.general.showsFilmstrip",
        "settings.general.showsInspector", "settings.general.confirmsDelete",
        "settings.general.navigationTransitions", "settings.general.resetUsageHint",
        "settings.general.continuousReading",
        "settings.general.readingDirection", "settings.general.readingDirection.leftToRight",
        "settings.general.readingDirection.rightToLeft",
        "settings.general.usageHintReset",
        "settings.fileAssociations.title", "settings.fileAssociations.selectCommon",
        "settings.fileAssociations.showAll", "settings.fileAssociations.showLess",
        "settings.fileAssociations.apply", "settings.fileAssociations.applying",
        "settings.fileAssociations.defaultImageView", "settings.fileAssociations.defaultOther",
        "settings.fileAssociations.defaultUnknown", "settings.fileAssociations.success",
        "settings.fileAssociations.partialSuccess", "settings.fileAssociations.failure",
        "settings.fileAssociations.invalidBundle", "settings.fileAssociations.unsupportedType",
        "settings.format.jpeg", "settings.format.png", "settings.format.gif",
        "settings.format.webp", "settings.format.heic", "settings.format.tiff",
        "settings.format.bmp", "settings.format.heif", "settings.format.avif",
        "settings.format.svg"
    ]

    static let emptyStateKeys = [
        "emptyState.title",
        "emptyState.message",
        "emptyState.open",
        "emptyState.browseFolder"
        , "emptyState.recent", "emptyState.clearRecent"
    ]

    static let errorStateKeys = [
        "errorState.retry"
    ]

    static let titleBarKeys = [
        "titleBar.browseCurrentFolder",
        "titleBar.back",
        "titleBar.forward",
        "titleBar.showFolder",
        "titleBar.showImage"
        , "titleBar.more"
    ]

    static let folderBrowserKeys = [
        "folderBrowser.searchPlaceholder",
        "folderBrowser.sort.name",
        "folderBrowser.sort.modified",
        "folderBrowser.sort.size",
        "folderBrowser.typeFilter.all",
        "folderBrowser.count.total", "folderBrowser.count.filtered", "folderBrowser.count.selected",
        "folderBrowser.item.position", "folderBrowser.item.selected", "folderBrowser.item.notSelected",
        "folderBrowser.announcement.filtered", "folderBrowser.announcement.completed",
        "folderBrowser.button.trash",
        "folderBrowser.button.move",
        "folderBrowser.button.rename",
        "folderBrowser.button.more",
        "folderBrowser.state.loading.title",
        "folderBrowser.state.loading.message",
        "folderBrowser.state.emptyFolder.title",
        "folderBrowser.state.emptyFolder.message",
        "folderBrowser.state.filteredEmpty.title",
        "folderBrowser.state.filteredEmpty.message",
        "folderBrowser.state.loadFailed.title",
        "folderBrowser.button.retry",
        "folderBrowser.button.clearFilters",
        "folderBrowser.button.chooseAnotherFolder",
        "folderBrowser.status.working",
        "folderBrowser.progress.trash", "folderBrowser.progress.move", "folderBrowser.progress.rename",
        "folderBrowser.progress.cancel", "folderBrowser.progress.cancelling",
        "folderBrowser.failure.cancelled",
        "folderBrowser.status.failure.one",
        "folderBrowser.status.failure.other",
        "folderBrowser.failure.emptyName",
        "folderBrowser.failure.invalidName",
        "folderBrowser.failure.sourceMissing",
        "folderBrowser.failure.destinationExists",
        "folderBrowser.failure.duplicateDestination",
        "folderBrowser.failure.trashFailed",
        "folderBrowser.failure.moveFailed",
        "folderBrowser.failure.renameFailed",
        "folderBrowser.recovery.heading",
        "folderBrowser.recovery.item",
        "folderBrowser.recovery.hiddenTemporaryHint",
        "folderBrowser.recovery.alert.title",
        "folderBrowser.recovery.alert.folder",
        "folderBrowser.operation.succeeded",
        "folderBrowser.operation.failed",
        "folderBrowser.operation.succeededAndFailed",
        "folderBrowser.operation.undo",
        "folderBrowser.operation.viewDetails", "folderBrowser.operation.detailsTitle",
        "batchRename.title",
        "batchRename.field.baseName",
        "batchRename.field.startNumber",
        "batchRename.field.padding",
        "batchRename.preview",
        "batchRename.button.cancel",
        "batchRename.button.rename",
        "batchRename.validation.baseNameRequired",
        "batchRename.validation.baseNameInvalid",
        "batchRename.validation.numberInvalid",
        "folderBrowser.confirmTrash.title",
        "folderBrowser.confirmTrash.message",
        "folderBrowser.confirmTrash.button",
        "folderBrowser.confirmTrash.cancel",
        "folderBrowser.movePanel.prompt",
        "folderBrowser.moveConflict.title",
        "folderBrowser.moveConflict.message",
        "folderBrowser.moveConflict.skip",
        "folderBrowser.moveConflict.keepBoth",
        "folderBrowser.moveConflict.cancel"
    ]

    static let inspectorKeys = [
        "inspector.title",
        "inspector.format",
        "inspector.pixels",
        "inspector.size",
        "inspector.modified",
        "inspector.captured",
        "inspector.camera",
        "inspector.file",
        "inspector.path", "inspector.colorSpace", "inspector.colorProfile",
        "inspector.bitDepth", "inspector.orientation", "inspector.copy",
        "inspector.reveal", "inspector.dock", "inspector.undock", "inspector.close",
        "inspector.exposureTime", "inspector.aperture", "inspector.isoSpeed", "inspector.focalLength",
        "inspector.noImage",
        "inspector.unknown"
    ]

    static let interactionKeys = [
        "viewer.confirmTrash.title",
        "viewer.confirmTrash.message",
        "viewer.confirmTrash.button",
        "viewer.confirmTrash.cancel",
        "unsavedChanges.title",
        "unsavedChanges.message",
        "unsavedChanges.button.save",
        "unsavedChanges.button.discard",
        "unsavedChanges.button.cancel",
        "unsavedChanges.transition.opening",
        "unsavedChanges.transition.navigating",
        "unsavedChanges.transition.renaming",
        "unsavedChanges.transition.movingToTrash",
        "unsavedChanges.transition.closing",
        "crop.button.cancel",
        "crop.button.apply",
        "folderBrowser.error.openFolder",
        "help.message",
        "help.searchPlaceholder", "help.noResults", "help.content",
        "usageHint.message", "usageHint.dismiss", "usageHint.accessibilityLabel",
        "viewer.continuousReading.accessibilityLabel",
        "viewer.announcement.loaded",
        "viewer.zoom.fit", "viewer.zoom.fitWithPercentage",
        "viewer.zoom.fitWidth", "viewer.zoom.fitWidthWithPercentage",
        "viewer.zoom.menu.tooltip", "viewer.zoom.menu.accessibilityLabel",
        "viewer.zoom.custom.menu", "viewer.zoom.custom.title", "viewer.zoom.custom.message",
        "viewer.zoom.custom.field", "viewer.zoom.custom.apply", "viewer.zoom.custom.cancel",
        "editing.history.limitReached", "editing.history.rebuildFailed",
        "menu.edit.undoNamed", "menu.edit.redoNamed",
        "editing.operation.rotateClockwise", "editing.operation.rotateCounterClockwise",
        "editing.operation.mirrorHorizontal", "editing.operation.mirrorVertical",
        "editing.operation.crop",
        "common.ok",
        "batchRename.defaultBaseName"
    ]

    static func text(_ key: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let localization = preferredLanguages.contains { $0.lowercased().hasPrefix("zh") } ? "zh-hans" : "en"
        let resourceBundle = packagedResourceBundle ?? Bundle.module
        guard let path = resourceBundle.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static var packagedResourceBundle: Bundle? {
        guard let url = Bundle.main.url(
            forResource: packagedResourceBundleName,
            withExtension: "bundle"
        ) else {
            return nil
        }
        return Bundle(url: url)
    }
}
