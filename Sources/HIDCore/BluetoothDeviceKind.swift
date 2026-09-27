/// Coarse device type derived from the Bluetooth Class of Device, for icons and host filtering.
public enum BluetoothDeviceKind: String, CaseIterable, Codable, Sendable {
    case desktop, laptop, tablet, computer, phone, keyboard, pointer, audio, other

    private static let majorComputer: UInt32 = 1
    private static let majorPhone: UInt32 = 2
    private static let majorAudio: UInt32 = 4
    private static let majorPeripheral: UInt32 = 5

    public init(classOfDevice: UInt32) {
        let major = (classOfDevice >> 8) & 0x1F
        let minor = (classOfDevice >> 2) & 0x3F
        switch major {
        case Self.majorComputer:
            switch minor {
            case 1: self = .desktop
            case 3: self = .laptop
            case 7: self = .tablet
            default: self = .computer
            }
        case Self.majorPhone: self = .phone
        case Self.majorAudio: self = .audio
        case Self.majorPeripheral:
            switch (minor >> 4) & 0x3 {
            case 1: self = .keyboard
            case 2, 3: self = .pointer
            default: self = .other
            }
        default: self = .other
        }
    }

    /// SF Symbol name, matching what the macOS Bluetooth menu shows.
    public var symbolName: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .tablet: return "ipad"
        case .computer: return "pc"
        case .phone: return "iphone"
        case .keyboard: return "keyboard"
        case .pointer: return "computermouse"
        case .audio: return "headphones"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// Only computers can act as the HID host this app connects to.
    public var canHostKeyboard: Bool {
        switch self {
        case .desktop, .laptop, .tablet, .computer: return true
        default: return false
        }
    }
}
