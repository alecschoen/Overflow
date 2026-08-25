import AppKit
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Overflow: launch-at-login toggle failed: \(error)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusBarDelegate {
    private var statusBar: StatusBarController!
    private let popout = PopoutController()
    private lazy var onboarding = OnboardingWindowController()
    private let settings = SettingsPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        statusBar.delegate = self
        popout.statusBar = statusBar
        settings.openSetupGuide = { [weak self] in self?.onboarding.show() }

        // Warm the icon cache once the bar has settled: off-screen windows
        // can't be captured on macOS 26, so snapshot icons while visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [popout] in
            popout.primeCache()
        }

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            onboarding.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onboarding.show()
        return false
    }

    // MARK: StatusBarDelegate

    func chevronLeftClicked(_ button: NSStatusBarButton) {
        settings.close()
        if statusBar.isCollapsed {
            popout.toggle(relativeTo: button)
        } else {
            // Inline-expanded: the chevron collapses everything back.
            statusBar.setCollapsed(true)
        }
    }

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: statusBar.isCollapsed ? "Show Stashed Icons Inline" : "Stash Icons",
            action: #selector(toggleCollapsed),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refresh = NSMenuItem(title: "Refresh Icon Images", action: #selector(refreshIcons), keyEquivalent: "")
        refresh.target = self
        refresh.toolTip = "Briefly reveals the stashed icons to re-photograph them"
        menu.addItem(refresh)

        let help = NSMenuItem(title: "Setup & Permissions…", action: #selector(showOnboarding), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Overflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleCollapsed() {
        statusBar.setCollapsed(!statusBar.isCollapsed)
    }

    @objc private func showSettings() {
        popout.close()
        settings.open(relativeTo: statusBar.chevronItem.button)
    }

    @objc private func refreshIcons() {
        popout.flashRefreshCache(onlyIfMissing: false)
    }

    @objc private func showOnboarding() {
        onboarding.show()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
