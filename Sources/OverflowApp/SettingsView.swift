import SwiftUI
import AppKit

/// Settings content, DisplayVolume-style: compact rows, mini switches,
/// permission status lines, Quit at the bottom. Hosted in an AnchoredPanel.
struct SettingsPanelView: View {
    let openSetupGuide: () -> Void

    @AppStorage("iconsPerRow") private var iconsPerRow = 5
    @AppStorage("iconSpacing") private var iconSpacing = 2.0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var screenGranted = Permissions.screenRecording
    @State private var axGranted = Permissions.accessibility
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overflow")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Icons per row")
                    Spacer()
                    Text("\(iconsPerRow)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $iconsPerRow, in: 1...12)
                        .labelsHidden()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Spacing between icons")
                        Spacer()
                        Text("\(Int(iconSpacing)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $iconSpacing, in: 0...12, step: 1)
                        .controlSize(.small)
                }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue != LaunchAtLogin.isEnabled {
                            LaunchAtLogin.toggle()
                        }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }
            .font(.callout)

            permissionRow(
                title: "Screen Recording",
                granted: screenGranted,
                detail: "Draws the real icons in the tray"
            ) {
                Permissions.requestScreenRecording()
                Permissions.openScreenRecordingSettings()
            }

            permissionRow(
                title: "Accessibility",
                granted: axGranted,
                detail: "Forwards tray clicks to the real items"
            ) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }

            Divider()

            HStack {
                Button("Setup Guide…") { openSetupGuide() }
                    .controlSize(.small)
                Spacer()
                Button("Quit Overflow") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onReceive(timer) { _ in
            screenGranted = Permissions.screenRecording
            axGranted = Permissions.accessibility
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, detail: String, open: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption)
                Text(granted ? "Granted" : detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings") { open() }
                    .controlSize(.small)
            }
        }
    }
}
