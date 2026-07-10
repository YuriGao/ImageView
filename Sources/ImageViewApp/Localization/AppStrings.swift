import Foundation

enum AppStrings {
    static let menuKeys = [
        "menu.file", "menu.view", "menu.image", "menu.window", "menu.help",
        "menu.app.settings", "menu.app.quit",
        "menu.file.open", "menu.file.openRecent", "menu.file.rename", "menu.file.reveal", "menu.file.copyPath", "menu.file.moveToTrash", "menu.file.close", "menu.file.noRecentImages",
        "menu.view.previousImage", "menu.view.nextImage", "menu.view.actualSize", "menu.view.zoomToFit", "menu.view.showFilmstrip", "menu.view.showInfo", "menu.view.enterFullScreen",
        "menu.image.rotateClockwise", "menu.image.rotateCounterclockwise", "menu.image.flipHorizontal", "menu.image.flipVertical", "menu.image.crop", "menu.image.saveEdits", "menu.image.saveAs", "menu.image.discardEdits",
        "menu.window.minimize", "menu.window.zoom", "menu.window.bringAllToFront",
        "menu.help.imageView"
    ]

    static func text(_ key: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let localization = preferredLanguages.contains { $0.lowercased().hasPrefix("zh") } ? "zh-hans" : "en"
        guard let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
