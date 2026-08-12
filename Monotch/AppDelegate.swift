import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchWindowController.shared.showCollapsed()
        closeAutoPresentedWindows()
    }

    /// Monotch's UI is the notch panel; Settings and Help are opened on request from
    /// the menu bar. SwiftUI still presents a window scene at launch, so anything that
    /// shows up on its own gets dismissed. Runs after launch settles, because those
    /// windows are not on screen yet during `applicationDidFinishLaunching`.
    private func closeAutoPresentedWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window is NSPanel == false && window.isVisible {
                window.close()
            }
        }
    }

    /// Closing Settings or Help must not take the app down with it — the notch panel
    /// is the app, and it is an `NSPanel` that does not count as a window here.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
