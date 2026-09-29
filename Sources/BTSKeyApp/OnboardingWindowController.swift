import AppKit
import SwiftUI
import HIDCore
import InputCapture

/// Hosts the SwiftUI guide in a plain titled window; one instance for the app's lifetime.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model = OnboardingModel()
    private let settings: Settings
    private let session: SessionController

    init(settings: Settings, session: SessionController) {
        self.settings = settings
        self.session = session
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "\(AppInfo.name) 시작하기"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        InputCapturePermissionRequester.request = { InputPermissions.request() }
        model.onFinish = { [weak self] in self?.finish() }
        model.onRequestBluetooth = { [weak self] in self?.session.start() }
        model.onConnect = { [weak self] in
            self?.session.start()
            self?.session.connect()
        }
        model.onSelectTarget = { [weak self] in
            self?.finish()
            SystemSettingsLinks.open(SystemSettingsLinks.bluetooth)
        }
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.setContentSize(NSSize(width: 720, height: 460))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Opens the guide at `step`; help items that explain one thing jump straight to its page.
    func show(at step: OnboardingStep = .welcome) {
        model.hotkeyText = settings.hotkey.displayString
        model.targetName = settings.targetName
        model.refreshPermissions()
        model.step = step
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        settings.hasCompletedOnboarding = true
        model.stopPolling()
        // Whatever the user did in the guide, the app must now be listening for the iMac.
        session.start()
    }
}
