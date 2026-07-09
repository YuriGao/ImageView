import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindowIfNeeded()
        for url in pendingOpenURLs {
            mainWindowController?.open(url: url)
        }
        pendingOpenURLs.removeAll()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindowIfNeeded()
        if mainWindowController == nil {
            pendingOpenURLs.append(contentsOf: urls)
        } else if let first = urls.first {
            mainWindowController?.open(url: first)
        }
    }

    private func showWindowIfNeeded() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
    }
}
