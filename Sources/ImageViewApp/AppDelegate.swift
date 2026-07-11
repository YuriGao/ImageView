import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let defaultApplicationService: DefaultApplicationServicing
    private var imageWindowControllers: [MainWindowController] = []
    private weak var activeImageWindowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var pendingLaunchURLs: [URL] = []
    private var didFinishLaunching = false
    private var didRequestTermination = false
    private let makeImageWindowController: (AppSettings) -> MainWindowController
    private let showImageWindow: (MainWindowController) -> Void
    private let openImageURL: (MainWindowController, URL) -> Void
    private let terminateApplication: () -> Void
    private weak var installedMainMenu: NSMenu?
    private var openRecentMenu: NSMenu?
    private var appearanceMenuItems: [AppAppearance: NSMenuItem] = [:]

    init(
        settings: AppSettings = .shared,
        defaultApplicationService: DefaultApplicationServicing = WorkspaceDefaultApplicationService(),
        makeImageWindowController: @escaping (AppSettings) -> MainWindowController = { MainWindowController(settings: $0) },
        showImageWindow: @escaping (MainWindowController) -> Void = { $0.showWindow(nil) },
        openImageURL: @escaping (MainWindowController, URL) -> Void = { $0.open(url: $1) },
        terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.settings = settings
        self.defaultApplicationService = defaultApplicationService
        self.makeImageWindowController = makeImageWindowController
        self.showImageWindow = showImageWindow
        self.openImageURL = openImageURL
        self.terminateApplication = terminateApplication
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching else {
            pendingLaunchURLs.append(contentsOf: urls)
            return
        }
        openURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func finishLaunching(installMenu: Bool = true) {
        applyAppearance()
        didFinishLaunching = true
        if imageWindowControllers.isEmpty {
            showImageWindow(createImageWindow())
        }
        if installMenu {
            installMainMenuIfNeeded()
        }
        let urls = pendingLaunchURLs
        pendingLaunchURLs.removeAll()
        openURLs(urls)
    }

    @discardableResult
    private func createImageWindow() -> MainWindowController {
        let controller = makeImageWindowController(settings)
        controller.onSuccessfulOpen = { [weak self] url in
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            self?.rebuildOpenRecentMenu()
        }
        controller.onWindowDidBecomeKey = { [weak self] controller in
            self?.imageWindowDidBecomeKey(controller)
        }
        controller.onWindowDidClose = { [weak self] controller in
            self?.imageWindowDidClose(controller)
        }
        imageWindowControllers.append(controller)
        activeImageWindowController = controller
        return controller
    }

    func openURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let controller = imageWindowControllers.first(where: { !$0.hasAssignedOpenRequest }) ?? createImageWindow()
            activeImageWindowController = controller
            openImageURL(controller, url)
            showImageWindow(controller)
        }
        connectMenuTargets()
    }

    func imageWindowDidBecomeKey(_ controller: MainWindowController) {
        guard imageWindowControllers.contains(where: { $0 === controller }) else { return }
        activeImageWindowController = controller
        connectMenuTargets()
    }

    func imageWindowDidClose(_ controller: MainWindowController) {
        guard let index = imageWindowControllers.firstIndex(where: { $0 === controller }) else { return }
        imageWindowControllers.remove(at: index)
        if activeImageWindowController === controller {
            activeImageWindowController = imageWindowControllers.last
        }
        connectMenuTargets()
        guard imageWindowControllers.isEmpty, !didRequestTermination else { return }
        didRequestTermination = true
        terminateApplication()
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                settings: settings,
                defaultApplicationService: defaultApplicationService
            )
        }
        preferencesWindowController?.showWindow(sender)
        preferencesWindowController?.window?.makeKeyAndOrderFront(sender)
    }

    private func installMainMenuIfNeeded() {
        let mainMenu = makeMainMenu()
        NSApp.mainMenu = mainMenu
        installedMainMenu = mainMenu
        configureHelpMenuSearchSuppression()
        connectMenuTargets()
    }

    func configureHelpMenuSearchSuppression() {
        NSApp.helpMenu = NSMenu(title: "ImageViewHelpSearch")
    }

    func makeMainMenu(preferredLanguages: [String] = Locale.preferredLanguages) -> NSMenu {
        let text: (String) -> String = { AppStrings.text($0, preferredLanguages: preferredLanguages) }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "ImageView", action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "ImageView")
        appMenuItem.submenu = appMenu
        let preferencesMenuItem = NSMenuItem(title: text("menu.app.settings"), action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferencesMenuItem.target = self
        appMenu.addItem(preferencesMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(text("menu.app.quit")) \(ProcessInfo.processInfo.processName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem(title: text("menu.file"), action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: text("menu.file"))
        fileMenuItem.submenu = fileMenu

        let openMenuItem = NSMenuItem(title: text("menu.file.open"), action: #selector(openImage(_:)), keyEquivalent: "o")
        openMenuItem.target = self
        fileMenu.addItem(openMenuItem)

        let openRecentItem = NSMenuItem(title: text("menu.file.openRecent"), action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: text("menu.file.openRecent"))
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)
        fileMenu.addItem(.separator())
        self.openRecentMenu = openRecentMenu
        rebuildOpenRecentMenu()

        let renameMenuItem = NSMenuItem(title: text("menu.file.rename"), action: #selector(MainWindowController.renameCurrentImage(_:)), keyEquivalent: "R")
        renameMenuItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(renameMenuItem)

        let revealMenuItem = NSMenuItem(title: text("menu.file.reveal"), action: #selector(MainWindowController.revealCurrentImageInFinder(_:)), keyEquivalent: "r")
        revealMenuItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(revealMenuItem)

        let copyPathMenuItem = NSMenuItem(title: text("menu.file.copyPath"), action: #selector(MainWindowController.copyCurrentImagePath(_:)), keyEquivalent: "c")
        copyPathMenuItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(copyPathMenuItem)

        fileMenu.addItem(.separator())

        let moveToTrashMenuItem = NSMenuItem(title: text("menu.file.moveToTrash"), action: #selector(MainWindowController.moveCurrentImageToTrash(_:)), keyEquivalent: "\u{8}")
        fileMenu.addItem(moveToTrashMenuItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: text("menu.file.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let viewMenuItem = NSMenuItem(title: text("menu.view"), action: nil, keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: text("menu.view"))
        viewMenuItem.submenu = viewMenu

        viewMenu.addItem(NSMenuItem(title: text("menu.view.previousImage"), action: #selector(MainWindowController.showPreviousImage(_:)), keyEquivalent: "\u{F702}"))
        viewMenu.addItem(NSMenuItem(title: text("menu.view.nextImage"), action: #selector(MainWindowController.showNextImage(_:)), keyEquivalent: "\u{F703}"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(NSMenuItem(title: text("menu.view.actualSize"), action: #selector(MainWindowController.actualSize(_:)), keyEquivalent: "0"))
        viewMenu.addItem(NSMenuItem(title: text("menu.view.zoomToFit"), action: #selector(MainWindowController.zoomToFit(_:)), keyEquivalent: "9"))
        viewMenu.addItem(.separator())

        let toggleFilmstripMenuItem = NSMenuItem(title: text("menu.view.showFilmstrip"), action: #selector(MainWindowController.toggleFilmstrip(_:)), keyEquivalent: "f")
        toggleFilmstripMenuItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleFilmstripMenuItem)

        let toggleInspectorMenuItem = NSMenuItem(title: text("menu.view.showInfo"), action: #selector(MainWindowController.toggleInspector(_:)), keyEquivalent: "i")
        toggleInspectorMenuItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleInspectorMenuItem)
        viewMenu.addItem(.separator())

        let appearanceMenuItem = NSMenuItem(title: text("menu.view.appearance"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: text("menu.view.appearance"))
        appearanceMenuItem.submenu = appearanceMenu
        viewMenu.addItem(appearanceMenuItem)

        let appearanceChoices: [(AppAppearance, String, Selector)] = [
            (.system, "menu.view.appearance.system", #selector(selectSystemAppearance(_:))),
            (.light, "menu.view.appearance.light", #selector(selectLightAppearance(_:))),
            (.dark, "menu.view.appearance.dark", #selector(selectDarkAppearance(_:)))
        ]
        appearanceMenuItems.removeAll()
        for (appearance, titleKey, action) in appearanceChoices {
            let item = NSMenuItem(title: text(titleKey), action: nil, keyEquivalent: "")
            item.action = action
            item.target = self
            appearanceMenu.addItem(item)
            appearanceMenuItems[appearance] = item
        }
        updateAppearanceMenuState()
        viewMenu.addItem(.separator())
        viewMenu.addItem(NSMenuItem(title: text("menu.view.enterFullScreen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))

        let editMenuItem = NSMenuItem(title: text("menu.image"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: text("menu.image"))
        editMenuItem.submenu = editMenu

        let rotateClockwiseMenuItem = NSMenuItem(title: text("menu.image.rotateClockwise"), action: #selector(MainWindowController.rotateClockwise(_:)), keyEquivalent: "]")
        editMenu.addItem(rotateClockwiseMenuItem)

        let rotateCounterClockwiseMenuItem = NSMenuItem(title: text("menu.image.rotateCounterclockwise"), action: #selector(MainWindowController.rotateCounterClockwise(_:)), keyEquivalent: "[")
        editMenu.addItem(rotateCounterClockwiseMenuItem)

        let mirrorHorizontalMenuItem = NSMenuItem(title: text("menu.image.flipHorizontal"), action: #selector(MainWindowController.mirrorHorizontal(_:)), keyEquivalent: "h")
        mirrorHorizontalMenuItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(mirrorHorizontalMenuItem)

        let mirrorVerticalMenuItem = NSMenuItem(title: text("menu.image.flipVertical"), action: #selector(MainWindowController.mirrorVertical(_:)), keyEquivalent: "v")
        mirrorVerticalMenuItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(mirrorVerticalMenuItem)

        let cropMenuItem = NSMenuItem(title: text("menu.image.crop"), action: #selector(MainWindowController.startCropping(_:)), keyEquivalent: "k")
        cropMenuItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(cropMenuItem)

        editMenu.addItem(.separator())

        let saveEditsMenuItem = NSMenuItem(title: text("menu.image.saveEdits"), action: #selector(MainWindowController.saveEdits(_:)), keyEquivalent: "s")
        editMenu.addItem(saveEditsMenuItem)

        let saveEditsAsMenuItem = NSMenuItem(title: text("menu.image.saveAs"), action: #selector(MainWindowController.saveEditsAs(_:)), keyEquivalent: "S")
        saveEditsAsMenuItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(saveEditsAsMenuItem)

        let discardEditsMenuItem = NSMenuItem(title: text("menu.image.discardEdits"), action: #selector(MainWindowController.discardEdits(_:)), keyEquivalent: "z")
        discardEditsMenuItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(discardEditsMenuItem)

        let windowMenuItem = NSMenuItem(title: text("menu.window"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: text("menu.window"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: text("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: text("menu.window.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem(title: text("menu.window.bringAllToFront"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        mainMenu.addItem(windowMenuItem)

        let helpMenuItem = NSMenuItem(title: text("menu.help"), action: nil, keyEquivalent: "")
        helpMenuItem.submenu = NSMenu(title: text("menu.help"))
        let helpItem = NSMenuItem(title: text("menu.help.imageView"), action: #selector(showHelp(_:)), keyEquivalent: "?")
        helpItem.target = self
        helpMenuItem.submenu?.addItem(helpItem)
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }

    @objc private func openImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        openURLs(panel.urls)
    }

    @objc private func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("menu.help.imageView")
        alert.informativeText = "Open an image, use the View menu to browse and zoom, and use the Image menu to edit or save changes."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func appearanceName(for appearance: AppAppearance) -> NSAppearance.Name? {
        switch appearance {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    func applyAppearance(to application: NSApplication = NSApp) {
        application.appearance = Self.appearanceName(for: settings.appearance)
            .flatMap(NSAppearance.init(named:))
    }

    @objc private func selectSystemAppearance(_ sender: Any?) {
        selectAppearance(.system)
    }

    @objc private func selectLightAppearance(_ sender: Any?) {
        selectAppearance(.light)
    }

    @objc private func selectDarkAppearance(_ sender: Any?) {
        selectAppearance(.dark)
    }

    private func selectAppearance(_ appearance: AppAppearance) {
        settings.appearance = appearance
        applyAppearance()
        updateAppearanceMenuState()
    }

    private func updateAppearanceMenuState() {
        for (appearance, item) in appearanceMenuItems {
            item.state = appearance == settings.appearance ? .on : .off
        }
    }

    @objc private func openRecentImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openURLs([url])
    }

    private func rebuildOpenRecentMenu() {
        guard let openRecentMenu else { return }
        openRecentMenu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs.prefix(10)
        guard !urls.isEmpty else {
            let emptyItem = NSMenuItem(title: AppStrings.text("menu.file.noRecentImages"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openRecentMenu.addItem(emptyItem)
            return
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentImage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            openRecentMenu.addItem(item)
        }
    }

    private func connectMenuTargets() {
        let target = menuTargetImageController
        connectControllerActions(in: installedMainMenu, target: target)
    }

    private func connectControllerActions(in menu: NSMenu?, target: MainWindowController?) {
        guard let menu else { return }
        for item in menu.items {
            if let action = item.action,
               MainWindowController.menuCommand(for: action) != nil ||
               action == #selector(MainWindowController.toggleFilmstrip(_:)) ||
               action == #selector(MainWindowController.toggleInspector(_:)) {
                item.target = target
            }
            connectControllerActions(in: item.submenu, target: target)
        }
    }

    private var menuTargetImageController: MainWindowController? {
        if let keyWindow = NSApp.keyWindow,
           let keyController = imageWindowControllers.first(where: { $0.window === keyWindow }) {
            return keyController
        }
        if let activeImageWindowController,
           imageWindowControllers.contains(where: { $0 === activeImageWindowController }) {
            return activeImageWindowController
        }
        return imageWindowControllers.last
    }

    var imageWindowCount: Int { imageWindowControllers.count }
    var imageWindowControllersForTesting: [MainWindowController] { imageWindowControllers }
    var pendingURLsForTesting: [URL] { pendingLaunchURLs }
    var activeImageWindowControllerForTesting: MainWindowController? { activeImageWindowController }

    func finishLaunchingForTesting(installMenu: Bool = true) {
        finishLaunching(installMenu: installMenu)
    }

    func connectMenuTargetsForTesting() {
        connectMenuTargets()
    }

    func setInstalledMainMenuForTesting(_ menu: NSMenu) {
        installedMainMenu = menu
    }

    func showPreferencesForTesting() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                settings: settings,
                defaultApplicationService: defaultApplicationService
            )
        }
    }
}
