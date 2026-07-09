import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var pendingLaunchURL: URL?
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        showWindowIfNeeded()
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
        mainWindowController?.showWindow(nil)
    }
}
