import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onApplicationDidResignActive: (() -> Void)?
    var onApplicationWillTerminate: (() -> Void)?
    var onShowMainWindowRequested: (() -> Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowMainWindowRequest),
            name: .showMainWindow,
            object: nil
        )
    }

    func applicationDidResignActive(_ notification: Notification) {
        onApplicationDidResignActive?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        onApplicationWillTerminate?()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onShowMainWindowRequested?()
        return true
    }

    @objc
    private func handleShowMainWindowRequest() {
        onShowMainWindowRequested?()
    }
}
