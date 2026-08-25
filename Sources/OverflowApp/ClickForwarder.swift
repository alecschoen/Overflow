import AppKit
import ApplicationServices

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
        let point = CGPoint(x: frame.midX, y: frame.midY)
        if Self.isUnderNotch(frame) {
            // A synthetic click at notch coordinates hits nothing. Activate
            // the item through its accessibility element instead — AXPress
            // works regardless of physical visibility. AX calls can block
            // while the opened menu tracks, so run off the main thread.
            let pids = Self.candidatePIDs()
            Task.detached {
                if !Self.axActivate(near: point, rightClick: rightClick, pids: pids) {
                    Self.postClick(at: point, right: rightClick)
                }
            }
        } else {
            Self.postClick(at: point, right: rightClick)
        }
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

    /// On-screen windows that could be UI a status-item click opened: any
    /// window at all — menus, popovers, floating panels, and plain
    /// normal-level panels (ChatGPT, DockDoor). On macOS 26 the clicked
    /// item's window is owned by Control Centre, not the real app, so
    /// ownership can't identify the opener — watch globally and diff
    /// against a before-click snapshot instead.
    static func onScreenUIWindowIDs() -> Set<CGWindowID> {
        guard let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var result = Set<CGWindowID>()
        for info in raw {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int, Int32(pid) != myPID,
                  (0...1000).contains(layer), layer != 24, layer != 25
            else { continue }
            if let owner = info[kCGWindowOwnerName as String] as? String, owner == "Window Server" { continue }
            result.insert(CGWindowID(number))
        }
        return result
    }

    /// Current frames (CG coordinates) of the given on-screen windows.
    static func frames(of windowIDs: Set<CGWindowID>) -> [CGRect] {
        guard !windowIDs.isEmpty,
              let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [CGRect] = []
        for info in raw {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  windowIDs.contains(CGWindowID(number)),
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            result.append(frame)
        }
        return result
    }

    /// True when the frame overlaps a notch — the strip of menu bar where no
    /// pixels exist and no synthetic click can land.
    static func isUnderNotch(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        for screen in NSScreen.screens {
            guard screen.safeAreaInsets.top > 0,
                  let left = screen.auxiliaryTopLeftArea,
                  let right = screen.auxiliaryTopRightArea else { continue }
            // AppKit and CG global coordinates share the x axis; flip y.
            let cgTop = primary.frame.maxY - screen.frame.maxY
            guard abs(frame.minY - cgTop) < 44 else { continue }
            if frame.maxX > left.maxX && frame.minX < right.minX { return true }
        }
        return false
    }

    /// Running apps most likely to own a status item first.
    static func candidatePIDs() -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier > 0 }
            .sorted { rank($0) < rank($1) }
            .map(\.processIdentifier)
    }

    private static func rank(_ app: NSRunningApplication) -> Int {
        switch app.activationPolicy {
        case .accessory: return 0   // menu-bar-only apps
        case .regular: return 1
        case .prohibited: return 2
        @unknown default: return 3
        }
    }

    /// Finds the status-item accessibility element at `point` (searching
    /// every app's AXExtrasMenuBar) and performs AXPress / AXShowMenu on it.
    /// Blocking — call off the main thread.
    nonisolated static func axActivate(near point: CGPoint, rightClick: Bool, pids: [pid_t]) -> Bool {
        for pid in pids {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extras = extrasRef, CFGetTypeID(extras) == AXUIElementGetTypeID()
            else { continue }
            let bar = extras as! AXUIElement
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AnyObject]
            else { continue }
            for childAny in children {
                guard CFGetTypeID(childAny) == AXUIElementGetTypeID() else { continue }
                let child = childAny as! AXUIElement
                guard let frame = axFrame(child), frame.insetBy(dx: -4, dy: -4).contains(point) else { continue }
                var action = kAXPressAction as String
                if rightClick, axSupports(child, action: "AXShowMenu") { action = "AXShowMenu" }
                return AXUIElementPerformAction(child, action as CFString) == .success
            }
        }
        return false
    }

    private nonisolated static func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)   // AX uses CG global coordinates
    }

    private nonisolated static func axSupports(_ element: AXUIElement, action: String) -> Bool {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(element, &namesRef) == .success,
              let names = namesRef as? [String] else { return false }
        return names.contains(action)
    }

    /// Posts a synthetic click in global CG coordinates (needs Accessibility).
    nonisolated static func postClick(at point: CGPoint, right: Bool) {
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
    private var clickMonitor: Any?
    private var openedWindows = Set<CGWindowID>()
    private var sawUI = false
    private var completed = false

    init(initialWindows: Set<CGWindowID>, onDone: @escaping () -> Void) {
        self.initialWindows = initialWindows
        self.onDone = onDone
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Clicks inside the UI the forwarded click opened keep the bar
        // revealed (panels like ChatGPT's are anchored to the item and die
        // if it re-stashes under them); any click elsewhere re-stashes —
        // that same click dismisses the panel anyway.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleGlobalClick() }
        }
    }

    private func handleGlobalClick() {
        guard !completed, sawUI else { return }
        let location = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return }
        let cgPoint = CGPoint(x: location.x, y: primary.frame.maxY - location.y)
        let frames = ClickForwarder.frames(of: openedWindows)
        guard !frames.contains(where: { $0.contains(cgPoint) }) else { return }
        // Give the click a beat to land before the bar re-layouts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finish()
        }
    }

    /// Always completes (calls onDone exactly once) — the expansion hold it
    /// guards must be released even when a new click supersedes this watcher.
    func cancel() {
        finish()
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(start)
        let current = ClickForwarder.onScreenUIWindowIDs()
        let newWindows = current.subtracting(initialWindows)
        if !newWindows.isEmpty {
            sawUI = true
            openedWindows.formUnion(newWindows)
        }
        if sawUI {
            let stillOpen = !current.isDisjoint(with: openedWindows)
            if !stillOpen || elapsed > 90 { finish() }
        } else if elapsed > 4.0 {
            // (Generous: the AX fallback path can take a moment to search
            // every app's menu bar extras before the menu appears.)
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
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        onDone()
    }
}
