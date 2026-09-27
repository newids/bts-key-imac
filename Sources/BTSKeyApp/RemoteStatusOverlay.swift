import AppKit

/// A small box pinned under the menu bar for as long as input goes to the iMac,
/// so the current mode is always visible (the 1 s HUD alone was easy to miss).
final class RemoteStatusOverlay {
    private static let size = NSSize(width: 236, height: 52)
    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenEdgeInset: CGFloat = 8

    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "iMac 입력 중")
    private let hintLabel = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1.5
        background.layer?.borderColor = NSColor.systemOrange.cgColor

        let icon = NSImageView(image: NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        icon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        icon.frame = NSRect(x: 12, y: 13, width: 28, height: 26)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 48, y: 26, width: Self.size.width - 56, height: 18)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 48, y: 9, width: Self.size.width - 56, height: 15)

        [icon, titleLabel, hintLabel].forEach(background.addSubview)
        panel.contentView = background
    }

    /// `anchor` is the status item's frame in screen coordinates; the box sits right under it.
    func show(hotkey: String, anchor: NSRect?) {
        hintLabel.stringValue = "\(hotkey) 로 MacBook 입력 복귀"
        guard position(under: anchor) else { return }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position(under anchor: NSRect?) -> Bool {
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.contains(rect.origin) } } ?? NSScreen.main
        guard let screen else { return false }
        let top = screen.visibleFrame.maxY - Self.gapBelowMenuBar
        let preferredX = (anchor?.midX ?? screen.frame.maxX) - Self.size.width / 2
        let x = min(max(preferredX, screen.frame.minX + Self.screenEdgeInset), screen.frame.maxX - Self.size.width - Self.screenEdgeInset)
        panel.setFrameOrigin(NSPoint(x: x, y: top - Self.size.height))
        return true
    }
}
