import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var pendingLaunchURL: URL?
    private var didFinishLaunching = false
    private var renameMenuItem: NSMenuItem?
    private var revealMenuItem: NSMenuItem?
    private var copyPathMenuItem: NSMenuItem?
    private var moveToTrashMenuItem: NSMenuItem?

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
            mainWindowController = MainWindowController()
        }
        connectMenuTargets()
        mainWindowController?.showWindow(nil)
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

        self.renameMenuItem = renameMenuItem
        self.revealMenuItem = revealMenuItem
        self.copyPathMenuItem = copyPathMenuItem
        self.moveToTrashMenuItem = moveToTrashMenuItem
        NSApp.mainMenu = mainMenu
        connectMenuTargets()
    }

    private func connectMenuTargets() {
        let target = mainWindowController
        renameMenuItem?.target = target
        revealMenuItem?.target = target
        copyPathMenuItem?.target = target
        moveToTrashMenuItem?.target = target
    }
}
