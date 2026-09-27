import ApplicationServices
import CoreGraphics

/// Accessibility (event tap) and Input Monitoring (keyboard listening) permissions.
public enum InputPermissions {
    public static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    public static var isInputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    /// Prompts the system dialogs for any permission that is still missing.
    public static func request() {
        if !isAccessibilityTrusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !isInputMonitoringGranted {
            _ = CGRequestListenEventAccess()
        }
    }

    public static var allGranted: Bool { isAccessibilityTrusted && isInputMonitoringGranted }
}
