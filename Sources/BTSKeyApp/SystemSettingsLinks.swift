import AppKit
import CoreBluetooth
import InputCapture

/// Deep links into System Settings and the live status of every permission the app needs.
enum SystemSettingsLinks {
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let inputMonitoring = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    static let bluetoothPrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
    static let bluetooth = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

enum AppPermission: CaseIterable {
    case bluetooth
    case accessibility
    case inputMonitoring

    var title: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .accessibility: return "손쉬운 사용"
        case .inputMonitoring: return "입력 모니터링"
        }
    }

    var reason: String {
        switch self {
        case .bluetooth: return "iMac에 키보드·마우스로 연결합니다."
        case .accessibility: return "iMac 입력 중 MacBook의 키·트랙패드 이벤트를 가로챕니다."
        case .inputMonitoring: return "키 입력과 Caps Lock을 읽습니다."
        }
    }

    var isGranted: Bool {
        switch self {
        case .bluetooth: return CBManager.authorization == .allowedAlways
        case .accessibility: return InputPermissions.isAccessibilityTrusted
        case .inputMonitoring: return InputPermissions.isInputMonitoringGranted
        }
    }

    var settingsURL: URL {
        switch self {
        case .bluetooth: return SystemSettingsLinks.bluetoothPrivacy
        case .accessibility: return SystemSettingsLinks.accessibility
        case .inputMonitoring: return SystemSettingsLinks.inputMonitoring
        }
    }

    static var allGranted: Bool { allCases.allSatisfy(\.isGranted) }
}
