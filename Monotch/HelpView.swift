import SwiftUI

struct HelpView: View {
    @State private var isShowingEULA = false

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
        .sheet(isPresented: $isShowingEULA) {
            EULAView()
        }
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
                Text("Monotch is licensed under the terms of the End User License Agreement (EULA). SF Symbols and system frameworks are © Apple Inc. and used under the Xcode and Apple SDK license terms. Lyrics are fetched from LRCLIB and remain the property of their rights holders.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(alignment: .firstTextBaseline) {
                    Button(action: { isShowingEULA = true }) {
                        Text("View EULA")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Text("Support: fatihyavuz.js@gmail.com")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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

struct EULAView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("End User License Agreement")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                Text(verbatim: eulaText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 520, height: 460)
    }

    private var eulaText: String {
        """
        MONOTCH END USER LICENSE AGREEMENT (EULA)

        Last Updated: July 20, 2026

        This End User License Agreement ("Agreement" or "EULA") is a binding legal agreement between you (the "End User" or "you") and Fatih Yavuz ("Developer" or "we") governing your use of the Monotch application ("Licensed Application"). 

        By downloading, installing, or using the Licensed Application from the Apple App Store or otherwise, you agree to be bound by the terms of this Agreement. If you do not agree to these terms, do not download, install, or use the Licensed Application.

        1. ACKNOWLEDGMENT AND PARTIES
        This Agreement is concluded solely between you and the Developer, and not with Apple Inc. ("Apple"). The Developer, and not Apple, is solely responsible for the Licensed Application and the content thereof.

        2. SCOPE OF LICENSE
        Developer grants you a non-exclusive, non-transferable, non-sublicensable, limited license to install and use the Licensed Application for personal, non-commercial purposes on any Apple-branded products running macOS ("Apple Device") that you own or control, and as permitted by the Usage Rules set forth in the Apple Media Services Terms of Service (the "Usage Rules").

        3. LICENSE RESTRICTIONS
        Except as explicitly permitted by this Agreement or applicable law, you shall not, and shall not permit any third party to:
        a) Redistribute, resell, rent, lease, lend, publish, or sublicense the Licensed Application.
        b) Modify, port, translate, adapt, or create derivative works of the Licensed Application.
        c) Decompile, reverse engineer, disassemble, decrypt, or attempt to derive the source code of the Licensed Application, in whole or in part, without the prior written consent of the Developer.
        d) Share the Licensed Application or make its functionality available to multiple users over a network.

        4. MAINTENANCE AND SUPPORT
        Developer is solely responsible for providing any maintenance and support services with respect to the Licensed Application, as specified in this EULA or as required under applicable law. Both you and the Developer acknowledge that Apple has no obligation whatsoever to furnish any maintenance and support services with respect to the Licensed Application.

        5. WARRANTY AND REFUND POLICY
        Developer provides the Licensed Application "AS IS" and "AS AVAILABLE," without warranty of any kind, express or implied. To the maximum extent permitted by applicable law, Developer disclaims all warranties, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, and non-infringement.
        In the event of any failure of the Licensed Application to conform to any applicable warranty, you may notify Apple, and Apple will refund the purchase price for the Licensed Application to you. To the maximum extent permitted by applicable law, Apple will have no other warranty obligation whatsoever with respect to the Licensed Application, and any other claims, losses, liabilities, damages, costs, or expenses attributable to any failure to conform to any warranty will be the Developer’s sole responsibility.

        6. PRODUCT CLAIMS
        Both you and the Developer acknowledge that the Developer, and not Apple, is responsible for addressing any claims by you or any third party relating to the Licensed Application or your possession and/or use of the Licensed Application, including, but not limited to:
        a) Product liability claims;
        b) Any claim that the Licensed Application fails to conform to any applicable legal or regulatory requirement; and
        c) Claims arising under consumer protection, privacy, or similar legislation.

        7. INTELLECTUAL PROPERTY RIGHTS
        Both you and the Developer acknowledge that, in the event of any third-party claim that the Licensed Application or your possession and use of the Licensed Application infringes that third party’s intellectual property rights, the Developer (and not Apple) will be solely responsible for the investigation, defense, settlement, and discharge of any such intellectual property infringement claim.

        8. LEGAL COMPLIANCE
        You represent and warrant that:
        a) You are not located in a country that is subject to a U.S. Government embargo, or that has been designated by the U.S. Government as a “terrorist supporting” country; and
        b) You are not listed on any U.S. Government list of prohibited or restricted parties.

        9. THIRD-PARTY NOTICES AND TERMS
        The Licensed Application may include or use third-party libraries, services, or frameworks. You must comply with applicable third-party terms when using the Licensed Application:
        a) SF Symbols and Apple system frameworks are © Apple Inc., used under the Apple SDK and Xcode license terms.
        b) Lyrics data is provided by LRCLIB (lrclib.net); lyrics remain the property of their respective rights holders.
        c) You agree not to violate any agreements with your Internet Service Provider, Apple App Store, or any other third party while using the Licensed Application.

        10. THIRD-PARTY BENEFICIARY
        Both you and the Developer acknowledge and agree that Apple, and Apple’s subsidiaries, are third-party beneficiaries of this Agreement, and that, upon your acceptance of the terms and conditions of this Agreement, Apple will have the right (and will be deemed to have accepted the right) to enforce this Agreement against you as a third-party beneficiary thereof.

        11. LIMITATION OF LIABILITY
        IN NO EVENT SHALL THE DEVELOPER BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT, OR CONSEQUENTIAL DAMAGES WHATSOEVER, INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, LOSS OF DATA, BUSINESS INTERRUPTION, OR ANY OTHER COMMERCIAL DAMAGES OR LOSSES, ARISING OUT OF OR RELATED TO YOUR USE OR INABILITY TO USE THE LICENSED APPLICATION, HOWEVER CAUSED, REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT, TORT, OR OTHERWISE).

        12. DEVELOPER CONTACT INFORMATION
        For any questions, support, complaints, or claims regarding the Licensed Application, please contact:
        Fatih Yavuz
        Email: fatihyavuz.js@gmail.com
        """
    }
}
