import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchWindowController.shared.showCollapsed()
    }

    // Without this, macOS window-state restoration reopens whatever window
    // (e.g. Settings) was on screen when the app last quit. Monotch has no
    // windows worth restoring, so disable it app-wide.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotchWindowController.shared.hideCompletely()
    }
}
