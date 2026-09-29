/// Coarse device type derived from the Bluetooth Class of Device, for icons and host filtering.
public enum BluetoothDeviceKind: String, CaseIterable, Codable, Sendable {
    case desktop, laptop, tablet, computer, phone, keyboard, pointer, audio, other
    /// No class of device on record. A host that started the pairing itself is stored this way,
    /// and so are phones, tablets and watches paired through iCloud.
    case unknown

    private static let majorComputer: UInt32 = 1
    private static let majorPhone: UInt32 = 2
    private static let majorAudio: UInt32 = 4
    private static let majorPeripheral: UInt32 = 5

    public init(classOfDevice: UInt32) {
        guard classOfDevice != 0 else {
            self = .unknown
            return
        }
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
        case .unknown: return "desktopcomputer"
        }
    }

    /// Only computers can act as the HID host this app connects to.
    public var canHostKeyboard: Bool {
        switch self {
        case .desktop, .laptop, .tablet, .computer: return true
        default: return false
        }
    }

    /// Whether a paired device is offered as a host. Without a class of device the pairing
    /// history decides: a device paired or served while the app was tracking is a host the user
    /// chose, one that was always there is one of the user's own devices.
    public func isHostCandidate(familiarity: HostFamiliarity) -> Bool {
        if canHostKeyboard { return true }
        guard self == .unknown else { return false }
        switch familiarity {
        case .new, .repaired, .returning: return true
        case .untried, .unpaired: return false
        }
    }
}
