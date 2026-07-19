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

        Window("Monotch Help", id: "monotch-help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
