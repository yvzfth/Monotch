//
//  NitcheApp.swift
//  Nitche
//
//  Created by Fatih Yavuz on 17.03.2026.
//

import SwiftUI
import AppKit

@main
struct NitcheApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var ui = NotchUIState.shared

    var body: some Scene {
        MenuBarExtra("Nitche", systemImage: "rectangle.topthird.inset.filled") {
            Button("Göster / Gizle") {
                NotchWindowController.shared.toggle()
            }
            Toggle("Nub hep görünsün", isOn: $ui.isPinned)
                .onChange(of: ui.isPinned) { _, pinned in
                    if pinned {
                        NotchWindowController.shared.showCollapsed()
                    } else {
                        NotchWindowController.shared.hideCompletely()
                    }
                }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
