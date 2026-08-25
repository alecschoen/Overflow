import AppKit

/// A status item in the menu bar, identified by its window.
///
/// NOTE (macOS 26): status items are hosted out-of-process — every item's
/// window is owned by Control Centre, and each item has one window copy per
/// display. So ownership tells us nothing about which app an item belongs
/// to, and scans must be restricted to a single display's menu-bar row to
/// avoid duplicates.
struct MenuBarItemInfo: Identifiable, Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    /// Global CG coordinates (origin at top-left of the primary display).
    let frame: CGRect

    var id: CGWindowID { windowID }

    /// True when the window owner actually identifies the owning app
    /// (pre-macOS-26 behavior). On macOS 26 everything is "Control Centre".
    var hasUsefulOwner: Bool {
        !["Control Centre", "Control Center", "SystemUIServer", "Window Server"].contains(ownerName)
    }
}

enum MenuBarScanner {
    /// NSWindow.Level.statusBar — the window level all status items live at.
    private static let statusBarLayer = 25
    /// Menu bar rows are at most this tall (33pt on notched Macs).
    private static let menuBarBandHeight: CGFloat = 44

    /// All status-item windows, including ones pushed off-screen,
    /// sorted left to right. Excludes this app's own windows.
    static func allStatusItems() -> [MenuBarItemInfo] {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var items: [MenuBarItemInfo] = []
        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusBarLayer,
                  let pid = info[kCGWindowOwnerPID as String] as? Int, Int32(pid) != myPID,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            // Status items are short strips. The width cap also filters out
            // collapse-spacer windows (ours is thousands of points wide).
            guard frame.height <= 40, frame.width <= 400, frame.width >= 4 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            items.append(MenuBarItemInfo(
                windowID: CGWindowID(number),
                pid: pid_t(pid),
                ownerName: owner,
                frame: frame
            ))
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        allStatusItems().first { $0.windowID == windowID }?.frame
    }

    /// Active display bounds in global CG coordinates.
    static func displayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        return (0..<Int(count)).map { CGDisplayBounds(ids[$0]) }
    }

    static func bounds(of displayID: CGDirectDisplayID) -> CGRect {
        CGDisplayBounds(displayID)
    }

    static func isFullyOffScreen(_ frame: CGRect) -> Bool {
        !displayBounds().contains { $0.intersects(frame) }
    }

    /// Items currently stashed on the given display: in that display's
    /// menu-bar row, but pushed fully off-screen by the collapsed separator
    /// (or clipped out by the notch).
    ///
    /// Filtering to one display's row is essential: every item has a window
    /// copy per display, and a display whose menu bar is auto-hidden parks
    /// its entire row off-screen — neither of those should count as stashed.
    static func hiddenItems(on display: CGRect) -> [MenuBarItemInfo] {
        let band = (display.minY - 2)...(display.minY + menuBarBandHeight)
        return allStatusItems().filter { item in
            band.contains(item.frame.minY) && isFullyOffScreen(item.frame)
        }
    }

    /// Items currently visible in the given display's menu-bar row. Only
    /// on-screen windows can be captured on macOS 26, so this is what the
    /// icon cache snapshots while the bar is (temporarily) expanded.
    static func onScreenItems(on display: CGRect) -> [MenuBarItemInfo] {
        let band = (display.minY - 2)...(display.minY + menuBarBandHeight)
        return allStatusItems().filter { item in
            band.contains(item.frame.minY) && !isFullyOffScreen(item.frame)
        }
    }
}
