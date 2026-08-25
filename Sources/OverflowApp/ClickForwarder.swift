import AppKit

/// Forwards a click from the tray popout to the real status item: slides the
/// stashed icons back on-screen, posts a synthetic click at the item's
/// location, then re-stashes once the UI the click opened has closed.
@MainActor
final class ClickForwarder {
    private var watcher: RecollapseWatcher?

    /// Returns true if the click was forwarded; false means we could only
    /// reveal the icons (no Accessibility permission, or the item never
    /// came on-screen).
    @discardableResult
    func activate(_ item: MenuBarItemInfo, rightClick: Bool, statusBar: StatusBarController) async -> Bool {
        watcher?.cancel()
        watcher = nil
        statusBar.acquireExpansion()

        guard Permissions.accessibility else {
            // Fallback: reveal the real icons for a few seconds so the user
            // can click the real thing.
            statusBar.releaseExpansion(after: 8)
            return false
        }

        // Wait for the menu bar to re-layout and the item to come on-screen.
        var found: CGRect?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if let frame = MenuBarScanner.frame(of: item.windowID), !MenuBarScanner.isFullyOffScreen(frame) {
                found = frame
                break
            }
        }
        guard found != nil else {
            statusBar.releaseExpansion(after: 5)
            return false
        }
        // One more beat so the slide animation settles, then re-read the frame.
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard let frame = MenuBarScanner.frame(of: item.windowID), !MenuBarScanner.isFullyOffScreen(frame) else {
            statusBar.releaseExpansion(after: 5)
            return false
        }

        let windowsBefore = Self.onScreenWindowIDs()
        Self.postClick(at: CGPoint(x: frame.midX, y: frame.midY), right: rightClick)
        watcher = RecollapseWatcher(initialWindows: windowsBefore) { [weak statusBar] in
            statusBar?.releaseExpansion()
        }
        return true
    }

    /// Every on-screen window ID (used as the "before" snapshot).
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result = Set<CGWindowID>()
        for info in raw {
            if let number = info[kCGWindowNumber as String] as? Int {
                result.insert(CGWindowID(number))
            }
        }
        return result
    }

    /// On-screen windows that look like transient UI a status-item click
    /// could have opened: menus, popovers, floating panels. On macOS 26 the
    /// clicked item's window is owned by Control Centre, not the real app,
    /// so ownership can't be used — watch globally instead.
    static func onScreenTransientWindowIDs() -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var result = Set<CGWindowID>()
        for info in raw {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int, Int32(pid) != myPID,
                  (1...1000).contains(layer), layer != 24, layer != 25
            else { continue }
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "Window Server" { continue }
            result.insert(CGWindowID(number))
        }
        return result
    }

    /// Posts a synthetic click in global CG coordinates (needs Accessibility).
    static func postClick(at point: CGPoint, right: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let button: CGMouseButton = right ? .right : .left
        guard let down = CGEvent(mouseEventSource: source,
                                 mouseType: right ? .rightMouseDown : .leftMouseDown,
                                 mouseCursorPosition: point,
                                 mouseButton: button),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: right ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: point,
                               mouseButton: button)
        else { return }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
    }
}

/// Watches for the transient UI (menu/popover/panel) opened by the forwarded
/// click; once it has closed again, re-stash the icons.
@MainActor
final class RecollapseWatcher {
    private let initialWindows: Set<CGWindowID>
    private let onDone: () -> Void
    private let start = Date()
    private var timer: Timer?
    private var openedWindows = Set<CGWindowID>()
    private var sawUI = false
    private var completed = false

    init(initialWindows: Set<CGWindowID>, onDone: @escaping () -> Void) {
        self.initialWindows = initialWindows
        self.onDone = onDone
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Always completes (calls onDone exactly once) — the expansion hold it
    /// guards must be released even when a new click supersedes this watcher.
    func cancel() {
        finish()
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(start)
        let current = ClickForwarder.onScreenTransientWindowIDs()
        let newWindows = current.subtracting(initialWindows)
        if !newWindows.isEmpty {
            sawUI = true
            openedWindows.formUnion(newWindows)
        }
        if sawUI {
            let stillOpen = !current.isDisjoint(with: openedWindows)
            if !stillOpen || elapsed > 90 { finish() }
        } else if elapsed > 2.5 {
            // The click did something without opening UI (or toggled an
            // existing window) — safe to re-stash.
            finish()
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        timer?.invalidate()
        timer = nil
        onDone()
    }
}
