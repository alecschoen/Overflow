import SwiftUI
import AppKit

/// Settings presented DisplayVolume-style: a frosted panel anchored under
/// the chevron (same chrome as the tray), compact rows, mini switches,
/// permission status lines, and a Quit button at the bottom.
@MainActor
final class SettingsPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SettingsPanelView>?
    private var globalMonitor: Any?
    private var anchor: NSPoint?
    var openSetupGuide: () -> Void = {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if isVisible { close() } else { open(relativeTo: button) }
    }

    func open(relativeTo button: NSStatusBarButton?) {
        let panel = ensurePanel()
        if let button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchor = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY - 6)
        } else if let screen = NSScreen.main {
            anchor = NSPoint(x: screen.visibleFrame.maxX - 160, y: screen.visibleFrame.maxY - 4)
        }
        if let effect = panel.contentView as? NSVisualEffectView {
            effect.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layoutPanel()
        panel.orderFrontRegardless()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: SettingsPanelView(openSetupGuide: { [weak self] in
            self?.close()
            self?.openSetupGuide()
        }))
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = effect.bounds

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effect
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    private func layoutPanel() {
        guard let panel, let hostingView, let anchor else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        var frame = NSRect(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height,
            width: size.width,
            height: size.height
        )
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.x - 1, y: anchor.y)) }) {
            frame.origin.x = min(frame.origin.x, screen.visibleFrame.maxX - size.width - 4)
            frame.origin.x = max(frame.origin.x, screen.visibleFrame.minX + 4)
        }
        panel.setFrame(frame, display: true)
        hostingView.frame = panel.contentView?.bounds ?? .zero
    }
}

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
