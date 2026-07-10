import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var mainWindowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var pendingLaunchURL: URL?
    private var didFinishLaunching = false
    private var preferencesMenuItem: NSMenuItem?
    private var toggleFilmstripMenuItem: NSMenuItem?
    private var toggleInspectorMenuItem: NSMenuItem?
    private var renameMenuItem: NSMenuItem?
    private var revealMenuItem: NSMenuItem?
    private var copyPathMenuItem: NSMenuItem?
    private var moveToTrashMenuItem: NSMenuItem?
    private var rotateClockwiseMenuItem: NSMenuItem?
    private var rotateCounterClockwiseMenuItem: NSMenuItem?
    private var mirrorHorizontalMenuItem: NSMenuItem?
    private var mirrorVerticalMenuItem: NSMenuItem?
    private var cropMenuItem: NSMenuItem?
    private var saveEditsMenuItem: NSMenuItem?
    private var saveEditsAsMenuItem: NSMenuItem?
    private var discardEditsMenuItem: NSMenuItem?
    private var openRecentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        showWindowIfNeeded()
        installMainMenuIfNeeded()
        if let url = pendingLaunchURL {
            mainWindowController?.open(url: url)
            pendingLaunchURL = nil
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last ?? urls.first else {
            return
        }

        guard didFinishLaunching else {
            pendingLaunchURL = url
            return
        }

        showWindowIfNeeded()
        mainWindowController?.open(url: url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showWindowIfNeeded() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(settings: settings)
            mainWindowController?.onSuccessfulOpen = { [weak self] url in
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self?.rebuildOpenRecentMenu()
            }
        }
        connectMenuTargets()
        mainWindowController?.showWindow(nil)
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(settings: settings)
        }
        preferencesWindowController?.showWindow(sender)
        preferencesWindowController?.window?.makeKeyAndOrderFront(sender)
    }

    private func installMainMenuIfNeeded() {
        NSApp.mainMenu = makeMainMenu()
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

        self.preferencesMenuItem = preferencesMenuItem
        self.toggleFilmstripMenuItem = toggleFilmstripMenuItem
        self.toggleInspectorMenuItem = toggleInspectorMenuItem
        self.renameMenuItem = renameMenuItem
        self.revealMenuItem = revealMenuItem
        self.copyPathMenuItem = copyPathMenuItem
        self.moveToTrashMenuItem = moveToTrashMenuItem
        self.rotateClockwiseMenuItem = rotateClockwiseMenuItem
        self.rotateCounterClockwiseMenuItem = rotateCounterClockwiseMenuItem
        self.mirrorHorizontalMenuItem = mirrorHorizontalMenuItem
        self.mirrorVerticalMenuItem = mirrorVerticalMenuItem
        self.cropMenuItem = cropMenuItem
        self.saveEditsMenuItem = saveEditsMenuItem
        self.saveEditsAsMenuItem = saveEditsAsMenuItem
        self.discardEditsMenuItem = discardEditsMenuItem
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showWindowIfNeeded()
        mainWindowController?.open(url: url)
    }

    @objc private func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("menu.help.imageView")
        alert.informativeText = "Open an image, use the View menu to browse and zoom, and use the Image menu to edit or save changes."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openRecentImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        showWindowIfNeeded()
        mainWindowController?.open(url: url)
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
        let target = mainWindowController
        preferencesMenuItem?.target = self
        toggleFilmstripMenuItem?.target = target
        toggleInspectorMenuItem?.target = target
        renameMenuItem?.target = target
        revealMenuItem?.target = target
        copyPathMenuItem?.target = target
        moveToTrashMenuItem?.target = target
        rotateClockwiseMenuItem?.target = target
        rotateCounterClockwiseMenuItem?.target = target
        mirrorHorizontalMenuItem?.target = target
        mirrorVerticalMenuItem?.target = target
        cropMenuItem?.target = target
        saveEditsMenuItem?.target = target
        saveEditsAsMenuItem?.target = target
        discardEditsMenuItem?.target = target
        connectControllerActions(in: NSApp.mainMenu, target: target)
    }

    private func connectControllerActions(in menu: NSMenu?, target: MainWindowController?) {
        guard let menu, let target else { return }
        for item in menu.items {
            if let action = item.action, target.responds(to: action) {
                item.target = target
            }
            connectControllerActions(in: item.submenu, target: target)
        }
    }
}
