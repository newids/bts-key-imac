import CoreBluetooth
import Foundation
import HIDCore
import SwiftUI

/// State for the first-run guide: current step, live permission status, and the actions it triggers.
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var permissions: [AppPermission: Bool] = [:]
    @Published var launchAtLogin = SupportActions.isLoginItemEnabled
    @Published var errorMessage: String?

    var onFinish: (() -> Void)?
    /// First use of Bluetooth: raises the system permission prompt.
    var onRequestBluetooth: (() -> Void)?
    var onConnect: (() -> Void)?
    var onSelectTarget: (() -> Void)?
    var hotkeyText = "⌥⌘K"
    var targetName: String?

    private var poll: Timer?

    init() { refreshPermissions() }

    var canGoBack: Bool { step.previous != nil }
    var isLast: Bool { step.next == nil }
    var allPermissionsGranted: Bool { AppPermission.allCases.allSatisfy { permissions[$0] == true } }

    func next() {
        if let next = step.next { step = next } else { onFinish?() }
    }

    func back() {
        if let previous = step.previous { step = previous }
    }

    func refreshPermissions() {
        permissions = Dictionary(uniqueKeysWithValues: AppPermission.allCases.map { ($0, $0.isGranted) })
    }

    func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPermissions() }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    func requestPermission(_ permission: AppPermission) {
        switch permission {
        case .bluetooth where CBManager.authorization == .notDetermined:
            // Not yet listed in System Settings; the prompt appears on first use instead.
            onRequestBluetooth?()
            refreshPermissions()
        case .accessibility, .inputMonitoring:
            InputCapturePermissionRequester.request()
            SystemSettingsLinks.open(permission.settingsURL)
        default:
            SystemSettingsLinks.open(permission.settingsURL)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = SupportActions.setLoginItem(enabled: enabled)
        launchAtLogin = SupportActions.isLoginItemEnabled
    }
}

/// Thin indirection so the model does not import InputCapture directly.
enum InputCapturePermissionRequester {
    static var request: () -> Void = {}
}
