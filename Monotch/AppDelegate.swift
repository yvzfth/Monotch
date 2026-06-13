import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchWindowController.shared.showCollapsed()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotchWindowController.shared.hideCompletely()
    }
}
