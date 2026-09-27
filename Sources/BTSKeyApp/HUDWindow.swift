import AppKit
import HIDCore

/// One-second, non-activating overlay that announces every mode change.
final class HUDWindow {
    private static let displayDuration: TimeInterval = 1.0
    private static let size = NSSize(width: 260, height: 90)

    private let panel: NSPanel
    private let label: NSTextField
    private var hideWork: DispatchWorkItem?

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
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.frame = NSRect(x: 0, y: (Self.size.height - 40) / 2, width: Self.size.width, height: 40)
        background.addSubview(label)
        panel.contentView = background
    }

    func show(_ message: HUDMessage) {
        label.stringValue = Self.text(for: message)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.midX - Self.size.width / 2,
                y: frame.minY + frame.height * 0.18
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [panel] in panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: work)
    }

    private static func text(for message: HUDMessage) -> String {
        switch message {
        case .connected: return "iMac 연결됨"
        case .remote: return "→ iMac"
        case .local: return "→ MacBook"
        case .disconnected: return "연결 끊김"
        case .pairedNewHost(let name): return "\(name) 페어링됨 · 연결 중"
        }
    }
}
