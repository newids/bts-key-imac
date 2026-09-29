import AppKit
import HIDCore
import QuartzCore

/// Non-activating overlay that announces connection and mode changes.
///
/// Layout: a tinted badge with a symbol (or a spinner while connecting), a title and one line
/// of detail. A gauge around the badge drains over the display time and the panel leaves when
/// it is empty; the close button in the top-right corner takes it down at once. It slides in,
/// the badge pops and sends out one ring. With Reduce Motion the slide, pop and ring are left out.
final class HUDWindow {
    private enum Metrics {
        static let size = NSSize(width: 410, height: 104)
        static let cornerRadius: CGFloat = 26
        static let badgeDiameter: CGFloat = 54
        static let inset: CGFloat = 26
        static let trailingInset: CGFloat = 38        // leaves the corner to the close button
        static let textGap: CGFloat = 16
        static let symbolPointSize: CGFloat = 23
        static let verticalPosition: CGFloat = 0.16   // share of the visible frame, from the bottom
        static let slideDistance: CGFloat = 14
        static let gaugeGap: CGFloat = 5              // between the badge and the gauge
        static let gaugeWidth: CGFloat = 3.5
        static let closeDiameter: CGFloat = 20
        static let closeInset: CGFloat = 9
    }

    private enum Timing {
        static let appear: TimeInterval = 0.24
        static let disappear: TimeInterval = 0.42
        static let contentSwap: TimeInterval = 0.18
        static let ring: TimeInterval = 0.85
    }

    private let panel: NSPanel
    private let badge = NSView()
    private let ring = CAShapeLayer()
    private let gaugeTrack = CAShapeLayer()
    private let gauge = CAShapeLayer()
    private let closeButton = CloseButton()
    private let symbol = NSImageView()
    private let spinner = NSProgressIndicator()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private var hideWork: DispatchWorkItem?
    private var isShowing = false
    private var latest: HUDPresentation?

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Metrics.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true    // takes clicks (for the close button) only while it is up
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = buildContent()
    }

    // MARK: - Showing

    func show(_ presentation: HUDPresentation) {
        hideWork?.cancel()
        latest = presentation
        if isShowing {
            // Already on screen: swap the content in place instead of replaying the entrance.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Timing.contentSwap
                textStack.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                // Dismissed or replaced while the text was fading: leave it to whoever came after.
                guard let self, self.isShowing, self.latest == presentation else { return }
                self.apply(presentation)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Timing.contentSwap
                    self.textStack.animator().alphaValue = 1
                }
                self.emphasize(presentation.tone)
                self.startGauge(presentation)
            }
        } else {
            apply(presentation)
            appear()
            emphasize(presentation.tone)
            startGauge(presentation)
        }
        let work = DispatchWorkItem { [weak self] in self?.disappear() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + presentation.duration, execute: work)
    }

    /// Takes the overlay down now, e.g. when the user cancels while "connecting" is showing.
    func dismiss() {
        hideWork?.cancel()
        guard isShowing else { return }
        disappear()
    }

    private func apply(_ presentation: HUDPresentation) {
        title.stringValue = presentation.title
        detail.stringValue = presentation.detail ?? ""
        detail.isHidden = presentation.detail == nil
        let color = Self.color(for: presentation.tone)
        badge.layer?.backgroundColor = color.cgColor
        badge.layer?.shadowColor = color.cgColor
        ring.strokeColor = color.cgColor
        gauge.strokeColor = color.cgColor
        if let name = presentation.symbolName {
            let configuration = NSImage.SymbolConfiguration(pointSize: Metrics.symbolPointSize, weight: .bold)
            symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: presentation.title)?
                .withSymbolConfiguration(configuration)
            symbol.isHidden = false
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        } else {
            symbol.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        }
        panel.setAccessibilityLabel([presentation.title, presentation.detail].compactMap { $0 }.joined(separator: ", "))
    }

    private func appear() {
        isShowing = true
        panel.ignoresMouseEvents = false
        let target = restingOrigin()
        // Shown again while still fading out: pick up from where the fade is instead of jumping.
        let isFadingOut = panel.isVisible && panel.alphaValue > 0
        let shouldMove = !Self.reducesMotion && !isFadingOut
        panel.setFrameOrigin(shouldMove ? NSPoint(x: target.x, y: target.y - Metrics.slideDistance) : target)
        if !isFadingOut { panel.alphaValue = 0 }
        textStack.alphaValue = 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.appear
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if shouldMove { panel.animator().setFrameOrigin(target) }
        }
    }

    private func disappear() {
        isShowing = false
        panel.ignoresMouseEvents = true   // a fading panel must not swallow clicks meant for what is under it
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.disappear
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, !self.isShowing else { return }
            self.spinner.stopAnimation(nil)
            self.panel.orderOut(nil)
        }
    }

    /// The badge pops and sends out one ring, so a change is noticed out of the corner of the eye.
    private func emphasize(_ tone: HUDPresentation.Tone) {
        guard !Self.reducesMotion, tone != .progress, let layer = badge.layer else { return }
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.62
        pop.toValue = 1
        pop.damping = 11
        pop.stiffness = 210
        pop.initialVelocity = 6
        pop.duration = pop.settlingDuration
        layer.add(pop, forKey: "pop")

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.75
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Timing.ring
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ring")
    }

    /// Drains the gauge from full to empty over the display time.
    private func startGauge(_ presentation: HUDPresentation) {
        gauge.removeAnimation(forKey: "drain")
        gauge.isHidden = !presentation.showsCountdown
        gaugeTrack.isHidden = !presentation.showsCountdown
        guard presentation.showsCountdown else { return }
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = 1
        drain.toValue = 0
        drain.duration = presentation.duration
        drain.timingFunction = CAMediaTimingFunction(name: .linear)
        drain.fillMode = .forwards
        drain.isRemovedOnCompletion = false
        gauge.add(drain, forKey: "drain")
    }

    @objc private func closeClicked() {
        dismiss()
    }

    private func restingOrigin() -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: frame.midX - Metrics.size.width / 2, y: frame.minY + frame.height * Metrics.verticalPosition)
    }

    // MARK: - Building

    private func buildContent() -> NSView {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Metrics.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        let badgeOrigin = NSPoint(x: Metrics.inset, y: (Metrics.size.height - Metrics.badgeDiameter) / 2)
        let badgeFrame = NSRect(origin: badgeOrigin, size: NSSize(width: Metrics.badgeDiameter, height: Metrics.badgeDiameter))

        // The ring sits under the badge, in the background's layer, so it can grow past the badge.
        ring.frame = badgeFrame
        ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: badgeFrame.size), transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.opacity = 0
        background.layer?.addSublayer(ring)

        // The gauge starts at twelve o'clock and runs clockwise around the badge.
        let gaugeRadius = Metrics.badgeDiameter / 2 + Metrics.gaugeGap
        let gaugePath = CGMutablePath()
        gaugePath.addArc(center: CGPoint(x: badgeFrame.midX, y: badgeFrame.midY), radius: gaugeRadius,
                         startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for layer in [gaugeTrack, gauge] {
            layer.frame = background.bounds
            layer.path = gaugePath
            layer.fillColor = nil
            layer.lineWidth = Metrics.gaugeWidth
            layer.lineCap = .round
            background.layer?.addSublayer(layer)
        }
        gaugeTrack.strokeColor = NSColor.white.withAlphaComponent(0.13).cgColor

        badge.frame = badgeFrame
        badge.wantsLayer = true
        badge.layer?.cornerRadius = Metrics.badgeDiameter / 2
        badge.layer?.masksToBounds = false
        badge.layer?.shadowOpacity = 0.55
        badge.layer?.shadowRadius = 11
        badge.layer?.shadowOffset = .zero
        // Scale around the centre: AppKit puts a view layer's anchor in its corner.
        badge.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        badge.layer?.position = CGPoint(x: badgeFrame.midX, y: badgeFrame.midY)
        background.addSubview(badge)

        symbol.frame = badge.bounds
        symbol.imageAlignment = .alignCenter
        symbol.imageScaling = .scaleNone
        symbol.contentTintColor = .white
        badge.addSubview(symbol)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.sizeToFit()
        spinner.frame.origin = NSPoint(x: (badge.bounds.width - spinner.frame.width) / 2,
                                       y: (badge.bounds.height - spinner.frame.height) / 2)
        spinner.isHidden = true
        badge.addSubview(spinner)

        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 12.5, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(detail)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(textStack)
        closeButton.frame = NSRect(x: Metrics.size.width - Metrics.closeInset - Metrics.closeDiameter,
                                   y: Metrics.size.height - Metrics.closeInset - Metrics.closeDiameter,
                                   width: Metrics.closeDiameter, height: Metrics.closeDiameter)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        background.addSubview(closeButton)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: background.leadingAnchor,
                                               constant: Metrics.inset + Metrics.badgeDiameter + Metrics.textGap),
            textStack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Metrics.trailingInset),
            textStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        return background
    }

    private static func color(for tone: HUDPresentation.Tone) -> NSColor {
        switch tone {
        case .progress: return NSColor(white: 0.2, alpha: 1)   // dark, so the light spinner stands out
        case .success: return .systemGreen
        case .remote: return .systemOrange
        case .local: return .systemBlue
        case .warning: return .systemRed
        case .notice: return .systemTeal
        }
    }

    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Small round close button. The panel never becomes key, so the first click has to count.
private final class CloseButton: NSButton {
    private static let symbolPointSize: CGFloat = 9

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .bold)
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "닫기")?.withSymbolConfiguration(configuration)
        imagePosition = .imageOnly
        contentTintColor = NSColor.white.withAlphaComponent(0.85)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        toolTip = "닫기"
        setAccessibilityLabel("닫기")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
