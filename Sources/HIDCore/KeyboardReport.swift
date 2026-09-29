/// Modifier bits of the keyboard input report (USB HID usages 0xE0–0xE7).
public struct KeyboardModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let leftControl = KeyboardModifiers(rawValue: 0x01)
    public static let leftShift = KeyboardModifiers(rawValue: 0x02)
    public static let leftAlt = KeyboardModifiers(rawValue: 0x04)
    public static let leftGUI = KeyboardModifiers(rawValue: 0x08)
    public static let rightControl = KeyboardModifiers(rawValue: 0x10)
    public static let rightShift = KeyboardModifiers(rawValue: 0x20)
    public static let rightAlt = KeyboardModifiers(rawValue: 0x40)
    public static let rightGUI = KeyboardModifiers(rawValue: 0x80)

    private static let firstModifierUsage: UInt8 = 0xE0
    private static let lastModifierUsage: UInt8 = 0xE7

    /// Returns the modifier bit for a modifier key usage, or nil for ordinary keys.
    public static func fromUsage(_ usage: UInt8) -> KeyboardModifiers? {
        guard (firstModifierUsage...lastModifierUsage).contains(usage) else { return nil }
        return KeyboardModifiers(rawValue: 1 << (usage - firstModifierUsage))
    }
}

/// Keyboard input report: 1 byte modifiers, 1 reserved byte, 6 key usages (6KRO),
/// then 1 byte for Apple's Fn/🌐 key (vendor page 0xFF, usage 0x03). A Mac host honours
/// that byte only for keyboards it marks as Apple's (`AppleVendorSupported`); a host that
/// treats this one as a generic Bluetooth keyboard drops it.
public struct KeyboardReport: Equatable, Sendable {
    public static let maximumKeys = 6
    public static let byteCount = 9

    public var modifiers: KeyboardModifiers
    public private(set) var keys: [UInt8]
    public var fn: Bool

    public init(modifiers: KeyboardModifiers = [], keys: [UInt8] = [], fn: Bool = false) {
        self.modifiers = modifiers
        self.keys = Array(keys.prefix(Self.maximumKeys))
        self.fn = fn
    }

    public var bytes: [UInt8] {
        let padding = [UInt8](repeating: 0, count: Self.maximumKeys - keys.count)
        return [modifiers.rawValue, 0] + keys + padding + [fn ? 1 : 0]
    }
}

/// Physical keys that can hold the Fn/🌐 key down on the host.
public enum FnSource: Hashable, Sendable {
    case fnKey
    case capsLock
}

/// Tracks the currently pressed keys and derives the report to send.
public struct KeyboardState: Sendable {
    public var modifiers: KeyboardModifiers = []
    /// Fn stays down while any source holds it, so releasing one never drops another's hold.
    private var fnHolders: Set<FnSource> = []
    private var pressedKeys: [UInt8] = []

    public var fn: Bool { !fnHolders.isEmpty }

    public mutating func setFn(held: Bool, by source: FnSource) {
        if held { fnHolders.insert(source) } else { fnHolders.remove(source) }
    }

    public init() {}

    public var report: KeyboardReport {
        KeyboardReport(modifiers: modifiers, keys: pressedKeys, fn: fn)
    }

    public var isIdle: Bool { modifiers.isEmpty && pressedKeys.isEmpty && !fn }

    public mutating func press(_ usage: UInt8) {
        guard !pressedKeys.contains(usage) else { return }
        pressedKeys.append(usage)
    }

    public mutating func release(_ usage: UInt8) {
        pressedKeys.removeAll { $0 == usage }
    }

    /// Releases every key and modifier. Sent when leaving remote mode so no key stays stuck on the host.
    public mutating func allUp() {
        modifiers = []
        fnHolders = []
        pressedKeys = []
    }
}
