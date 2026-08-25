import AppKit
import ScreenCaptureKit

/// A captured status-item image. Monochrome glyphs (the vast majority) are
/// flagged as templates so the tray can re-tint them to match its own
/// appearance — the menu bar may have rendered them black over a light
/// wallpaper or white over a dark one, and neither is guaranteed to be
/// readable on the tray's background.
struct CapturedIcon {
    let image: NSImage
    let isTemplate: Bool
}

/// Captures live images of status-item windows via ScreenCaptureKit.
enum IconCapturer {
    static func captureImages(for items: [MenuBarItemInfo]) async -> [CGWindowID: CapturedIcon] {
        guard !items.isEmpty, Permissions.screenRecording else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return [:]
        }
        var result: [CGWindowID: CapturedIcon] = [:]
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
                let image = NSImage(cgImage: cgImage, size: item.frame.size)
                result[item.windowID] = CapturedIcon(image: image, isTemplate: isMonochrome(cgImage))
            }
        }
        return result
    }

    /// True when every visible pixel is (near-)gray — a template-style glyph
    /// that can safely be re-tinted. Colorful icons return false and keep
    /// their original colors.
    private static func isMonochrome(_ cgImage: CGImage) -> Bool {
        let width = min(cgImage.width, 32)
        let height = min(cgImage.height, 32)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let alpha = pixels[i * 4 + 3]
            guard alpha > 40 else { continue }
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
            let maxChannel = max(r, g, b), minChannel = min(r, g, b)
            // >20% relative saturation on any visible pixel → colorful.
            if maxChannel > 0, (maxChannel - minChannel) * 5 > maxChannel { return false }
        }
        return true
    }

    /// Fallback when Screen Recording isn't granted: the owning app's icon.
    static func fallbackIcon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
