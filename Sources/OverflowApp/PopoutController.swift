import AppKit
import SwiftUI

struct PopoutItem: Identifiable {
    let info: MenuBarItemInfo
    var image: NSImage?
    var fallback: NSImage?
    var id: CGWindowID { info.windowID }
}

/// Owns the tray popout panel — a borderless, non-activating panel anchored
/// under the chevron, styled like a menu.
@MainActor
final class PopoutController: ObservableObject {
    @Published var items: [PopoutItem] = []
    @Published var hasScreenRecording = Permissions.screenRecording
    @Published var hasAccessibility = Permissions.accessibility

    weak var statusBar: StatusBarController?

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PopoutView>?
    private var globalMonitor: Any?
    private var refreshTimer: Timer?
    private var captureTask: Task<Void, Never>?
    private var flashInProgress = false
    private var lastAutoFlash: Date?
    private var cachedImages: [CGWindowID: NSImage] = [:]
    /// Top-right anchor of the panel in AppKit screen coordinates.
    private var anchor: NSPoint?
    /// CG bounds of the display whose menu bar we're showing icons from.
    private var targetDisplay: CGRect = CGDisplayBounds(CGMainDisplayID())
    private let forwarder = ClickForwarder()

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isVisible {
            close()
        } else {
            open(relativeTo: button)
        }
    }

    func open(relativeTo button: NSStatusBarButton) {
        hasScreenRecording = Permissions.screenRecording
        hasAccessibility = Permissions.accessibility

        let panel = ensurePanel()
        if let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchor = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY - 6)
            if let screen = window.screen,
               let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                targetDisplay = MenuBarScanner.bounds(of: displayID)
            }
        }
        if anchor == nil, let screen = NSScreen.main {
            // Fallback: hang off the top-right of the main screen.
            anchor = NSPoint(x: screen.visibleFrame.maxX - 8, y: screen.visibleFrame.maxY - 4)
        }
        refresh()
        layoutPanel()
        panel.orderFrontRegardless()
        statusBar?.popoutOpen = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func close() {
        statusBar?.popoutOpen = false
        panel?.orderOut(nil)
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Note: captureTask is left running — it balances an expansion hold
        // and must finish to release it.
    }

    /// Warm the icon cache shortly after launch, while a brief reveal is
    /// unobtrusive (the bar is in flux at login anyway).
    func primeCache() {
        flashRefreshCache(onlyIfMissing: true)
    }

    /// Stashed items with per-Space duplicates collapsed.
    ///
    /// Every Space (desktop / fullscreen app) has its own window copy of
    /// each status item, all at the same coordinates. Distinct items never
    /// overlap, so overlapping frames = the same item seen through several
    /// Spaces. Keep one copy per item, preferring the one we have a captured
    /// image for (that's the copy from the Space it was photographed on).
    private func dedupedHiddenItems() -> [MenuBarItemInfo] {
        let hidden = MenuBarScanner.hiddenItems(on: targetDisplay) // sorted by minX
        var result: [MenuBarItemInfo] = []
        for item in hidden {
            if let last = result.last, overlapsSubstantially(last.frame, item.frame) {
                if cachedImages[item.windowID] != nil && cachedImages[last.windowID] == nil {
                    result[result.count - 1] = item
                }
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func overlapsSubstantially(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        return intersection.width > min(a.width, b.width) * 0.5
    }

    func refresh() {
        let hidden = dedupedHiddenItems()
        items = hidden.map { info in
            PopoutItem(
                info: info,
                image: cachedImages[info.windowID],
                fallback: info.hasUsefulOwner ? IconCapturer.fallbackIcon(for: info.pid) : nil
            )
        }
        layoutPanel()
        // Off-screen windows can't be captured on macOS 26 — if any icon is
        // missing from the cache, briefly reveal the bar and snapshot it.
        flashRefreshCache(onlyIfMissing: true)
    }

    /// Briefly slides the stashed icons on-screen, captures fresh images of
    /// everything in the menu-bar row, and re-stashes. This is the only way
    /// to photograph them: macOS 26 refuses to capture off-screen windows.
    func flashRefreshCache(onlyIfMissing: Bool) {
        guard !flashInProgress, Permissions.screenRecording else { return }
        if onlyIfMissing {
            let hidden = dedupedHiddenItems()
            guard hidden.contains(where: { cachedImages[$0.windowID] == nil }) else { return }
            // Don't strobe the bar if some window persistently fails to capture.
            if let last = lastAutoFlash, Date().timeIntervalSince(last) < 30 { return }
            lastAutoFlash = Date()
        }
        guard let statusBar else { return }
        flashInProgress = true
        statusBar.acquireExpansion()
        captureTask = Task { [weak self] in
            // Wait for the bar to re-layout and the slide animation to settle.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self else { return }
            let visible = MenuBarScanner.onScreenItems(on: self.targetDisplay)
            let images = await IconCapturer.captureImages(for: visible)
            statusBar.releaseExpansion()
            self.flashInProgress = false
            self.cachedImages.merge(images) { _, new in new }
            if UserDefaults.standard.bool(forKey: "debugLogging") {
                let line = "\(Date()) flash: visible=\(visible.count) captured=\(images.count) cache=\(self.cachedImages.count) hidden=\(MenuBarScanner.hiddenItems(on: self.targetDisplay).count)\n"
                if let data = line.data(using: .utf8), let handle = FileHandle(forWritingAtPath: "/tmp/overflow-state.log") {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? line.write(toFile: "/tmp/overflow-state.log", atomically: true, encoding: .utf8)
                }
            }
            for index in self.items.indices {
                if let image = self.cachedImages[self.items[index].id] {
                    self.items[index].image = image
                }
            }
            self.layoutPanel()
        }
    }

    func activate(_ item: PopoutItem, rightClick: Bool) {
        close()
        guard let statusBar else { return }
        Task { await forwarder.activate(item.info, rightClick: rightClick, statusBar: statusBar) }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: PopoutView(controller: self))
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = effect.bounds

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
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
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    /// Resize to fit the SwiftUI content, keeping the top-right corner
    /// anchored under the chevron.
    private func layoutPanel() {
        guard let panel, let hostingView, let anchor else { return }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        size.width = max(size.width, 54)
        size.height = max(size.height, 40)
        // Centered under the chevron, clamped to the screen it lives on.
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
