import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Overflow Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage("iconsPerRow") private var iconsPerRow = 5
    @AppStorage("iconSpacing") private var iconSpacing = 2.0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tray layout").font(.headline)

                Stepper(value: $iconsPerRow, in: 1...12) {
                    HStack {
                        Text("Icons per row")
                        Spacer()
                        Text("\(iconsPerRow)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spacing between icons")
                        Spacer()
                        Text("\(Int(iconSpacing)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $iconSpacing, in: 0...12, step: 1)
                }
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    if newValue != LaunchAtLogin.isEnabled {
                        LaunchAtLogin.toggle()
                    }
                    launchAtLogin = LaunchAtLogin.isEnabled
                }

            Text("Changes apply the next time the tray opens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340)
    }
}
