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

    private func showWindowIfNeeded() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(settings: settings)
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
        guard NSApp.mainMenu == nil else {
            connectMenuTargets()
            return
        }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let preferencesMenuItem = NSMenuItem(title: "Settings…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferencesMenuItem.target = self
        appMenu.addItem(preferencesMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(ProcessInfo.processInfo.processName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let renameMenuItem = NSMenuItem(title: "Rename…", action: #selector(MainWindowController.renameCurrentImage(_:)), keyEquivalent: "R")
        renameMenuItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(renameMenuItem)

        let revealMenuItem = NSMenuItem(title: "Reveal in Finder", action: #selector(MainWindowController.revealCurrentImageInFinder(_:)), keyEquivalent: "r")
        revealMenuItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(revealMenuItem)

        let copyPathMenuItem = NSMenuItem(title: "Copy Path", action: #selector(MainWindowController.copyCurrentImagePath(_:)), keyEquivalent: "c")
        copyPathMenuItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(copyPathMenuItem)

        fileMenu.addItem(.separator())

        let moveToTrashMenuItem = NSMenuItem(title: "Move to Trash", action: #selector(MainWindowController.moveCurrentImageToTrash(_:)), keyEquivalent: "\u{8}")
        fileMenu.addItem(moveToTrashMenuItem)

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let toggleFilmstripMenuItem = NSMenuItem(title: "Show Filmstrip", action: #selector(MainWindowController.toggleFilmstrip(_:)), keyEquivalent: "f")
        toggleFilmstripMenuItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleFilmstripMenuItem)

        let toggleInspectorMenuItem = NSMenuItem(title: "Show Info", action: #selector(MainWindowController.toggleInspector(_:)), keyEquivalent: "i")
        toggleInspectorMenuItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleInspectorMenuItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let rotateClockwiseMenuItem = NSMenuItem(title: "Rotate Clockwise", action: #selector(MainWindowController.rotateClockwise(_:)), keyEquivalent: "]")
        editMenu.addItem(rotateClockwiseMenuItem)

        let rotateCounterClockwiseMenuItem = NSMenuItem(title: "Rotate Counterclockwise", action: #selector(MainWindowController.rotateCounterClockwise(_:)), keyEquivalent: "[")
        editMenu.addItem(rotateCounterClockwiseMenuItem)

        let mirrorHorizontalMenuItem = NSMenuItem(title: "Flip Horizontal", action: #selector(MainWindowController.mirrorHorizontal(_:)), keyEquivalent: "h")
        mirrorHorizontalMenuItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(mirrorHorizontalMenuItem)

        let mirrorVerticalMenuItem = NSMenuItem(title: "Flip Vertical", action: #selector(MainWindowController.mirrorVertical(_:)), keyEquivalent: "v")
        mirrorVerticalMenuItem.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(mirrorVerticalMenuItem)

        let cropMenuItem = NSMenuItem(title: "Crop", action: #selector(MainWindowController.startCropping(_:)), keyEquivalent: "k")
        cropMenuItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(cropMenuItem)

        editMenu.addItem(.separator())

        let saveEditsMenuItem = NSMenuItem(title: "Save Edits", action: #selector(MainWindowController.saveEdits(_:)), keyEquivalent: "s")
        editMenu.addItem(saveEditsMenuItem)

        let saveEditsAsMenuItem = NSMenuItem(title: "Save As…", action: #selector(MainWindowController.saveEditsAs(_:)), keyEquivalent: "S")
        saveEditsAsMenuItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(saveEditsAsMenuItem)

        let discardEditsMenuItem = NSMenuItem(title: "Discard Edits", action: #selector(MainWindowController.discardEdits(_:)), keyEquivalent: "z")
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
        NSApp.mainMenu = mainMenu
        connectMenuTargets()
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
    }
}
