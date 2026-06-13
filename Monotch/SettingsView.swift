import SwiftUI

struct SettingsView: View {
    @AppStorage("showNowPlaying") private var showNowPlaying = true
    @AppStorage("showCalendar") private var showCalendar = true
    @AppStorage("showSystem") private var showSystem = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nitche Settings")
                .font(.headline)

            GroupBox("Widgets") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Now Playing", isOn: $showNowPlaying)
                    Toggle("Calendar", isOn: $showCalendar)
                    Toggle("System Info", isOn: $showSystem)
                }
                .padding(8)
            }

            GroupBox("Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("Space", "Play / pause")
                    shortcutRow("← / →", "Switch tabs")
                    shortcutRow("↓ / ↑", "Lyrics / song info")
                    shortcutRow("L", "Toggle lyrics")
                    shortcutRow("M", "Mute / restore volume")
                }
                .padding(8)
            }

            Spacer()
            Text("Scroll ile widget sayfaları arasında geçiş yapabilir ve dosyaları island içine sürükleyip küçük bir shelf olarak saklayabilirsin.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 430, height: 370)
        .toolbar {
            ToolbarItemGroup {
                shortcutToolbarBadge("Space", "Play")
                shortcutToolbarBadge("← →", "Tabs")
                shortcutToolbarBadge("↓ ↑", "Lyrics")
                shortcutToolbarBadge("L", "Lyrics")
                shortcutToolbarBadge("M", "Mute")
            }
        }
    }

    private func shortcutRow(_ key: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .center)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutToolbarBadge(_ key: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}
