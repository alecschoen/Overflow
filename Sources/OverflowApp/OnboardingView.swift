import SwiftUI
import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Overflow"
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

struct OnboardingView: View {
    @State private var screenGranted = Permissions.screenRecording
    @State private var axGranted = Permissions.accessibility
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overflow").font(.title.bold())
                Text("A Windows-style overflow tray for your menu bar icons.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                step("1", "Hold ⌘ and drag menu bar icons to the **left** of the ❮ divider. They get stashed off the menu bar.")
                step("2", "Click the ❮ chevron to open the tray with your stashed icons. Click an icon to use it — left and right clicks both work.")
                step("3", "Option-click the chevron to temporarily show everything inline.")
            }

            Divider()

            Text("Permissions (both optional, both recommended)")
                .font(.headline)

            permissionRow(
                title: "Screen Recording",
                detail: "Draws the real, live icons in the tray. Without it you'll see app icons instead. macOS may ask you to relaunch Overflow after granting.",
                granted: screenGranted
            ) {
                Permissions.requestScreenRecording()
                Permissions.openScreenRecordingSettings()
            }

            permissionRow(
                title: "Accessibility",
                detail: "Forwards your tray clicks to the real icons. Without it, clicking a tray icon just reveals the menu bar icons for a few seconds.",
                granted: axGranted
            ) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onReceive(timer) { _ in
            screenGranted = Permissions.screenRecording
            axGranted = Permissions.accessibility
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.callout.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            Text(.init(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, grant: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.system(size: 18))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: grant)
                    .controlSize(.small)
            }
        }
    }
}
