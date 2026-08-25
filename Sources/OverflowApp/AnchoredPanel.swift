import SwiftUI
import AppKit

enum PanelChrome {
    static let cornerRadius: CGFloat = 16

    /// A rounded-rect mask at the panel's exact size. Shapes the
    /// behind-window blur itself — layer.cornerRadius alone leaves the
    /// backdrop square, poking past the rounded corners. Regenerated on
    /// every layout: a stretchable cap-inset mask leaves seam artifacts
    /// ("spikes") at the middle of each edge on Retina displays.
    static func mask(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
    }
}

/// A frosted, popover-style panel anchored under a status-item button —
/// the shared chrome for the tray, settings, and setup guide. Closes on
/// any click outside it.
@MainActor
final class AnchoredPanel<Content: View> {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<Content>?
    private var globalMonitor: Any?
    private var anchor: NSPoint?
    private let makeContent: () -> Content

    init(content: @escaping () -> Content) {
        makeContent = content
    }

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

        let hosting = NSHostingView(rootView: makeContent())
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = PanelChrome.cornerRadius
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
        (panel.contentView as? NSVisualEffectView)?.maskImage = PanelChrome.mask(size: frame.size)
    }
}
