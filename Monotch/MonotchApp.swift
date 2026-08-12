//
//  MonotchApp.swift
//  Monotch
//
//  Created by Fatih Yavuz on 17.03.2026.
//

import SwiftUI
import AppKit

@main
struct MonotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            MonotchCommands()
        }
        // SwiftUI presents the app's first scene at launch. Monotch's launch UI is the
        // notch panel, so Settings only opens from the menu bar.
        .defaultLaunchBehavior(.suppressed)

        Window("Monotch Help", id: "monotch-help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        // Singleton `Window` scenes are presented at launch by default. Monotch's
        // only launch-time UI is the notch panel itself, so Help opens on request.
        .defaultLaunchBehavior(.suppressed)
    }
}
