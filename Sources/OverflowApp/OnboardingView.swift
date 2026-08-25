import SwiftUI
import AppKit

/// The setup guide, shown in a frosted anchored panel (same chrome as the
/// tray and settings): quick-start steps plus permission status.
struct OnboardingView: View {
    let done: () -> Void

    @State private var screenGranted = Permissions.screenRecording
    @State private var axGranted = Permissions.accessibility
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Overflow")
                    .font(.headline)
                Text("A Windows-style overflow tray for your menu bar icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                step("1", "Hold ⌘ and drag menu bar icons to the **left** of the | divider — they get stashed off the menu bar.")
                step("2", "Click the v chevron to open the tray. Click an icon there to use it — left and right clicks both work.")
                step("3", "Option-click the chevron to temporarily show everything inline.")
            }

            Divider()

            Text("Permissions (optional, recommended)")
                .font(.caption.bold())

            permissionRow(
                title: "Screen Recording",
                granted: screenGranted,
                detail: "Draws the real icons in the tray — relaunch Overflow after granting"
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
                Spacer()
                Button("Done") { done() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onReceive(timer) { _ in
            screenGranted = Permissions.screenRecording
            axGranted = Permissions.accessibility
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Open Settings") { open() }
                    .controlSize(.small)
            }
        }
    }
}
