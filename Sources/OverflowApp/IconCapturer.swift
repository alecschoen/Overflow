import AppKit
import ScreenCaptureKit

/// Captures live images of status-item windows via ScreenCaptureKit.
/// Desktop-independent window capture works even for windows pushed
/// off-screen, which is exactly where stashed icons live.
enum IconCapturer {
    static func captureImages(for items: [MenuBarItemInfo]) async -> [CGWindowID: NSImage] {
        guard !items.isEmpty, Permissions.screenRecording else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return [:]
        }
        var result: [CGWindowID: NSImage] = [:]
        for item in items {
            guard let window = content.windows.first(where: { $0.windowID == item.windowID }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = 2 // capture at 2x for Retina crispness
            config.width = max(2, Int(item.frame.width) * scale)
            config.height = max(2, Int(item.frame.height) * scale)
            config.showsCursor = false
            config.captureResolution = .best
            config.ignoreShadowsSingleWindow = true
            config.backgroundColor = .clear
            if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                result[item.windowID] = NSImage(cgImage: cgImage, size: item.frame.size)
            }
        }
        return result
    }

    /// Fallback when Screen Recording isn't granted: the owning app's icon.
    static func fallbackIcon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
