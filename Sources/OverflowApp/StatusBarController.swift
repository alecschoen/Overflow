import AppKit

@MainActor
protocol StatusBarDelegate: AnyObject {
    func chevronLeftClicked(_ button: NSStatusBarButton)
    func buildContextMenu() -> NSMenu
}

/// Owns the two menu bar items:
///  - the chevron (always visible, opens the tray popout)
///  - the separator (anything ⌘-dragged to its left gets stashed)
///
/// Stashing uses the Hidden Bar / Ice trick: when collapsed, the separator's
/// length is set huge so everything to its left is pushed off-screen.
@MainActor
final class StatusBarController {
    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 9
    private static let collapsedDefaultsKey = "collapsed"

    let chevronItem: NSStatusItem
    let separatorItem: NSStatusItem
    weak var delegate: StatusBarDelegate?

    private(set) var isCollapsed: Bool
    /// Whether the tray popout is currently showing (drives the chevron
    /// direction: v closed, ^ open).
    var popoutOpen = false {
        didSet { apply() }
    }
    /// Reference count of "keep the icons revealed" holds (flash-capture,
    /// click forwarding). Icons re-stash when it drops to zero.
    private var expansionHolds = 0
    var isTemporarilyExpanded: Bool { expansionHolds > 0 }

    init() {
        let bar = NSStatusBar.system
        // Created first → sits to the right of the separator.
        chevronItem = bar.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = bar.statusItem(withLength: Self.separatorLength)
        chevronItem.autosaveName = "OverflowChevron"
        separatorItem.autosaveName = "OverflowSeparator"
        chevronItem.behavior = []
        separatorItem.behavior = []
        isCollapsed = UserDefaults.standard.object(forKey: Self.collapsedDefaultsKey) as? Bool ?? true
        configureButtons()
        apply()
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: Self.collapsedDefaultsKey)
        apply()
    }

    /// Slide stashed icons back on-screen without changing the saved state.
    /// Every acquire must be balanced by exactly one release.
    func acquireExpansion() {
        expansionHolds += 1
        apply()
    }

    func releaseExpansion() {
        expansionHolds = max(0, expansionHolds - 1)
        apply()
    }

    func releaseExpansion(after seconds: TimeInterval) {
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.releaseExpansion() }
        }
    }

    private func configureButtons() {
        if let button = chevronItem.button {
            button.target = self
            button.action = #selector(chevronClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Overflow — click to show stashed icons"
        }
        if let button = separatorItem.button {
            button.image = Self.makeSeparatorImage()
            button.target = self
            button.action = #selector(separatorClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "⌘-drag menu bar icons to the left of this divider to stash them"
        }
    }

    private func apply() {
        let expanded = !isCollapsed || isTemporarilyExpanded
        separatorItem.length = expanded ? Self.separatorLength : Self.collapsedLength
        let symbol: String
        if !isCollapsed {
            symbol = "chevron.right"   // showing everything inline — click to re-stash
        } else if popoutOpen {
            symbol = "chevron.up"      // tray is open below
        } else {
            symbol = "chevron.down"    // tray opens downward from here
        }
        chevronItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Overflow")
    }

    @objc private func chevronClicked() {
        guard let event = NSApp.currentEvent, let button = chevronItem.button else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(on: chevronItem)
        } else if event.modifierFlags.contains(.option) {
            setCollapsed(!isCollapsed)
        } else {
            delegate?.chevronLeftClicked(button)
        }
    }

    @objc private func separatorClicked() {
        showContextMenu(on: separatorItem)
    }

    private func showContextMenu(on item: NSStatusItem) {
        guard let menu = delegate?.buildContextMenu() else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private static func makeSeparatorImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 7, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 2.75, y: 1, width: 1.5, height: 14),
                xRadius: 0.75,
                yRadius: 0.75
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
