import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                gettingStartedSection
                shortcutsSection
                troubleshootingSection
                licensingSection
            }
            .padding(22)
        }
        .frame(width: 560, height: 640)
    }

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Monotch Help")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Version \(shortVersion) (Build \(buildVersion))")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("A reference for what the notch can do and how to resolve common issues.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var gettingStartedSection: some View {
        helpCard(title: "Getting Started") {
            helpRow(symbol: "cursorarrow.motionlines",
                    title: "Open the notch",
                    detail: "Hover the pointer over the notch, or press ⇧⌘N. Turn hover-open off in Settings › General.")
            helpRow(symbol: "hand.draw",
                    title: "Switch tabs",
                    detail: "Scroll horizontally on the notch, click a tab icon, or press ⌘1–⌘4.")
            helpRow(symbol: "rectangle.stack",
                    title: "Customize",
                    detail: "Right-click any card or tab icon in the notch to hide it. Re-enable and reorder everything in Settings.")
            helpRow(symbol: "tray.and.arrow.down",
                    title: "Shelf",
                    detail: "The Shelf card mirrors your Downloads folder by default. Point it at any folder from Settings › Clipboard & Shelf Cards.")
        }
    }

    private var shortcutsSection: some View {
        helpCard(title: "Keyboard Shortcuts") {
            helpShortcut("⇧⌘N", "Show the notch expanded")
            helpShortcut("⌘1 – ⌘4", "Jump to a tab")
            helpShortcut("⌘← / ⌘→", "Previous / next tab")
            helpShortcut("Space", "Take a photo — hold for video (camera tab)")
            helpShortcut("L", "Toggle lyrics (media tab, configurable)")
            helpShortcut("⇧⌘C / ⌥⌘C / ⌃⌘C", "Copy latest text / image / file")
            helpShortcut("⌘,", "Open Settings")
        }
    }

    private var troubleshootingSection: some View {
        helpCard(title: "Troubleshooting") {
            helpRow(symbol: "camera",
                    title: "Camera shows no image",
                    detail: "Check the camera isn't covered and the room has light. If macOS asks for permission, allow Monotch under System Settings › Privacy & Security › Camera.")
            helpRow(symbol: "fan",
                    title: "Fan controls disabled",
                    detail: "Fan control needs the privileged helper — approve it in System Settings › Login Items when prompted. Fanless Macs (MacBook Air) hide fan controls automatically. Silent and Balanced return to Auto when the CPU passes 75 °C.")
            helpRow(symbol: "music.note",
                    title: "Media not detected",
                    detail: "Monotch follows the system Now Playing item. Start playback in Music, Spotify, or a browser tab, then reopen the media tab. Playback control needs the Automation permission under Privacy & Security.")
            helpRow(symbol: "doc.on.clipboard",
                    title: "Clipboard history empty",
                    detail: "History fills as you copy. Clearing it from the Edit menu is permanent.")
        }
    }

    private var licensingSection: some View {
        helpCard(title: "Licensing & Credits") {
            VStack(alignment: .leading, spacing: 8) {
                Text("© 2026 Fatih Yavuz. All rights reserved.")
                    .font(.system(size: 12, weight: .semibold))
                Text("Monotch is licensed for personal use on the Mac it is installed on. SF Symbols and system frameworks are © Apple Inc. and used under the Xcode and Apple SDK license terms. Lyrics are fetched from LRCLIB and remain the property of their rights holders.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Support: fatihyavuz.js@gmail.com")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func helpCard<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func helpRow(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func helpShortcut(_ keys: String, _ purpose: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(purpose)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
