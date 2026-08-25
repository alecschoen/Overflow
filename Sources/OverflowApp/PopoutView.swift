import SwiftUI
import AppKit

/// The tray content: a wrapping row of stashed icons, Windows-style.
struct PopoutView: View {
    @ObservedObject var controller: PopoutController

    /// Icons per row before wrapping (like the Windows tray flyout) and the
    /// gap between them — both editable in the Settings window.
    @AppStorage("iconsPerRow") private var iconsPerRowSetting = 5
    @AppStorage("iconSpacing") private var iconSpacing = 2.0

    private var iconsPerRow: Int { max(1, iconsPerRowSetting) }

    private var rows: [[PopoutItem]] {
        stride(from: 0, to: controller.items.count, by: iconsPerRow).map {
            Array(controller.items[$0..<min($0 + iconsPerRow, controller.items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.items.isEmpty {
                emptyState
            } else {
                // Uniform cells sized to the largest icon → a perfect grid,
                // whatever mix of icon widths is stashed.
                let cellWidth = controller.items.map { min($0.info.frame.width, 200) }.max() ?? 28
                let cellHeight = controller.items.map(\.info.frame.height).max() ?? 24
                VStack(alignment: .leading, spacing: CGFloat(iconSpacing)) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: CGFloat(iconSpacing)) {
                            ForEach(row) { item in
                                ItemCell(item: item, cellSize: CGSize(width: cellWidth, height: cellHeight)) { rightClick in
                                    controller.activate(item, rightClick: rightClick)
                                }
                            }
                        }
                    }
                }
            }
            if !controller.hasScreenRecording || !controller.hasAccessibility {
                Divider()
                permissionHints
            }
        }
        .padding(8)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing stashed yet")
                .font(.headline)
            Text("Hold ⌘ and drag menu bar icons to the left of the ❮ divider — they'll live here instead.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(width: 290)
    }

    @ViewBuilder
    private var permissionHints: some View {
        Group {
            hintRows
        }
        .frame(width: 290, alignment: .leading)
    }

    @ViewBuilder
    private var hintRows: some View {
        if !controller.hasScreenRecording {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash").foregroundStyle(.secondary)
                Text("Grant Screen Recording to see the real icons")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Grant") {
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                }
                .controlSize(.small)
            }
        }
        if !controller.hasAccessibility {
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click.badge.clock").foregroundStyle(.secondary)
                Text("Grant Accessibility so clicks reach the icons")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Grant") {
                    Permissions.requestAccessibility()
                }
                .controlSize(.small)
            }
        }
    }
}

private struct ItemCell: View {
    let item: PopoutItem
    let cellSize: CGSize
    let action: (Bool) -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        iconView
            .frame(width: cellSize.width, height: cellSize.height)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.14) : Color.clear)
            )
            .onHover { hovering = $0 }
            .overlay(MouseCatcher(onClick: action))
            .help(item.info.hasUsefulOwner ? item.info.ownerName : "Menu bar item")
    }

    /// Icons render at the exact size their window has in the menu bar; the
    /// capture already includes the bar's own padding around the glyph.
    @ViewBuilder
    private var iconView: some View {
        if let icon = item.icon {
            // Template glyphs are re-tinted to the tray's own appearance so
            // they stay readable whatever color the menu bar drew them in.
            // Pure white / pure black — the same colors the menu bar itself
            // draws template glyphs in (label colors are slightly dimmed).
            Image(nsImage: icon.image)
                .renderingMode(icon.isTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: min(item.info.frame.width, 200), height: item.info.frame.height)
        } else if let fallback = item.fallback {
            Image(nsImage: fallback)
                .resizable()
                .frame(width: 22, height: 22)
                .frame(width: max(item.info.frame.width, 28), height: item.info.frame.height)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: max(item.info.frame.width, 28), height: item.info.frame.height)
        }
    }
}

/// Catches raw left/right mouse clicks (SwiftUI can't forward right-clicks).
private struct MouseCatcher: NSViewRepresentable {
    let onClick: (Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onClick: ((Bool) -> Void)?
        override func mouseDown(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) { onClick?(false) }
        override func rightMouseUp(with event: NSEvent) { onClick?(true) }
    }
}

